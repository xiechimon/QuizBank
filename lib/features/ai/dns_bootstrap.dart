import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// DoH 服务器（固定 IP 直连 + TLS SNI，不依赖系统 DNS）
///
/// 国内可直连的公共 DoH 服务，用于系统 DNS 无法解析（模拟器 DNS 失效、
/// 真机 DNS 污染等）时的兜底。IP 为各服务 A 记录，随版本更新。
class DohServer {
  /// 域名（用于 TLS SNI + 证书校验 + Host 头）
  final String host;

  /// 固定 IP（避免解析 DoH 域名时再次失败）
  final String ip;

  /// DoH 路径：阿里 `/resolve`，腾讯 `/dns-query`
  final String path;

  const DohServer(this.host, this.ip, this.path);
}

/// DNS 兜底解析器
///
/// 解析顺序：
/// 1. 系统 DNS（`InternetAddress.lookup`，带 5s 超时）
/// 2. 失败 → DoH 直连查询（多服务器依次尝试，固定 IP + SNI）
/// 3. 全部失败 → 抛 [SocketException]
///
/// 结果缓存 5 分钟，失败负缓存 20 秒，避免每次请求都重复 DoH。
class DnsBootstrap {
  DnsBootstrap._();
  static final DnsBootstrap instance = DnsBootstrap._();

  /// 测试注入：系统 DNS 解析器（默认 [InternetAddress.lookup]）
  @visibleForTesting
  Future<List<InternetAddress>> Function(String host)? systemLookup;

  /// 测试注入：DoH 查询（默认走固定 IP 直连；返回原始 JSON body）
  @visibleForTesting
  Future<String?> Function(String host)? dohQuery;

  /// 测试注入：清空缓存
  @visibleForTesting
  void resetCache() => _cache.clear();

  static const List<DohServer> dohServers = [
    DohServer('dns.alidns.com', '223.5.5.5', '/resolve'),
    DohServer('dns.alidns.com', '223.6.6.6', '/resolve'),
    DohServer('doh.pub', '119.29.29.29', '/dns-query'),
    DohServer('doh.pub', '1.12.12.12', '/dns-query'),
  ];

  static const Duration _cacheTtl = Duration(minutes: 5);
  static const Duration _negativeTtl = Duration(seconds: 20);
  static const Duration _lookupTimeout = Duration(seconds: 5);
  static const Duration _connectTimeout = Duration(seconds: 5);

  final Map<String, _CacheEntry> _cache = {};

  /// 解析 [host]，保证返回非空 IP 列表；失败抛 [SocketException]
  ///
  /// 顺序：缓存 → 系统 DNS → DoH 兜底。
  Future<List<InternetAddress>> resolve(String host) async {
    return _resolve(host, skipSystem: false);
  }

  /// 强制走 DoH（仅用于系统解析成功但连接失败的场景，如 DNS 污染返回假 IP）
  Future<List<InternetAddress>> resolveViaDoH(String host) async {
    return _resolve(host, skipSystem: true);
  }

  Future<List<InternetAddress>> _resolve(String host, {required bool skipSystem}) async {
    final key = host.toLowerCase();

    // 1. 缓存命中
    final cached = _cache[key];
    if (cached != null && cached.isValid) {
      if (cached.isNegative) {
        throw SocketException('Failed host lookup: $host');
      }
      return cached.addrs;
    }

    // 2. 系统 DNS
    if (!skipSystem) {
      try {
        final lookup = systemLookup ?? InternetAddress.lookup;
        final addrs = await lookup(host).timeout(_lookupTimeout);
        if (addrs.isNotEmpty) {
          _cache[key] = _CacheEntry.ok(addrs);
          return addrs;
        }
      } catch (_) {
        // 系统 DNS 失败，走 DoH 兜底
      }
    }

    // 3. DoH 兜底（多服务器依次尝试）
    try {
      final body = await (dohQuery ?? _dohQuery)(host);
      final addrs = parseDohAnswer(body);
      if (addrs.isNotEmpty) {
        _cache[key] = _CacheEntry.ok(addrs);
        return addrs;
      }
    } catch (_) {
      // 继续走失败路径
    }

    // 4. 负缓存 + 抛出
    _cache[key] = _CacheEntry.negative();
    throw SocketException('Failed host lookup: $host');
  }

  /// 内置 DoH 查询：固定 IP + TLS SNI，发 HTTP/1.0 GET（读至 EOF 即完整 body）
  Future<String?> _dohQuery(String host) async {
    for (final s in dohServers) {
      try {
        final body = await _queryVia(s, host);
        if (body != null && body.isNotEmpty) return body;
      } catch (_) {
        // 尝试下一个 DoH 服务器
      }
    }
    return null;
  }

  Future<String?> _queryVia(DohServer s, String host) async {
    final raw = await Socket.connect(
      s.ip,
      443,
      timeout: _connectTimeout,
    );
    // TLS：SNI + 证书校验均按域名 [s.host]，避免 IP 直连时主机名校验失败
    final socket = await SecureSocket.secure(raw, host: s.host);
    try {
      final name = Uri.encodeQueryComponent(host);
      socket.write('GET ${s.path}?name=$name&type=A HTTP/1.0\r\n'
          'Host: ${s.host}\r\n'
          'Accept: application/dns-json\r\n'
          'User-Agent: QuizBank-DnsBootstrap/1.0\r\n'
          '\r\n');
      await socket.flush();

      final sink = <int>[];
      await for (final chunk in socket) {
        sink.addAll(chunk);
      }
      final text = utf8.decode(sink, allowMalformed: true);

      // 解析 HTTP 响应：状态行 + 头 + body
      final headerEnd = text.indexOf('\r\n\r\n');
      if (headerEnd < 0) return null;
      final headerBlock = text.substring(0, headerEnd);
      final firstLine = headerBlock.split('\r\n').first;
      if (!firstLine.contains(' 200')) return null;

      // 有 Content-Length 则按长度截取（防握包残留）
      final contentLength = _headerInt(headerBlock, 'content-length');
      var body = text.substring(headerEnd + 4);
      if (contentLength != null && body.length > contentLength) {
        body = body.substring(0, contentLength);
      }
      return body;
    } finally {
      socket.destroy();
    }
  }

  static int? _headerInt(String headerBlock, String name) {
    for (final line in headerBlock.split('\r\n')) {
      final idx = line.toLowerCase().indexOf('$name:');
      if (idx == 0) {
        return int.tryParse(line.substring(line.indexOf(':') + 1).trim());
      }
    }
    return null;
  }

  /// 解析 DoH JSON 响应（dns-json 格式），提取 A 记录
  ///
  /// 纯函数，便于单测。示例：
  /// ```json
  /// {"Status":0,"Answer":[{"name":"opencode.ai.","type":1,"data":"172.65.90.20"}]}
  /// ```
  static List<InternetAddress> parseDohAnswer(String? body) {
    if (body == null || body.trim().isEmpty) return [];
    try {
      final obj = jsonDecode(body) as Map<String, dynamic>;
      if (obj['Status'] != 0) return [];
      final answers = obj['Answer'] as List<dynamic>? ?? [];
      final result = <InternetAddress>[];
      for (final a in answers) {
        if (a is! Map<String, dynamic>) continue;
        if (a['type'] != 1) continue; // 仅 A 记录
        final data = a['data'];
        if (data is! String) continue;
        final ip = InternetAddress.tryParse(data);
        if (ip != null) result.add(ip);
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}

class _CacheEntry {
  final List<InternetAddress> addrs;
  final bool negative;
  final DateTime expiry;

  _CacheEntry.ok(this.addrs)
      : negative = false,
        expiry = DateTime.now().add(DnsBootstrap._cacheTtl);

  _CacheEntry.negative()
      : addrs = const [],
        negative = true,
        expiry = DateTime.now().add(DnsBootstrap._negativeTtl);

  bool get isValid => DateTime.now().isBefore(expiry);
  bool get isNegative => negative;
}
