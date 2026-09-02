import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/features/ai/dns_bootstrap.dart';

void main() {
  group('DnsBootstrap.parseDohAnswer', () {
    test('解析标准 dns-json 响应中的 A 记录', () {
      const body = '{"Status":0,"TC":false,'
          '"Answer":['
          '{"name":"opencode.ai.","TTL":294,"type":1,"data":"172.65.90.21"},'
          '{"name":"opencode.ai.","TTL":294,"type":1,"data":"172.65.90.20"},'
          '{"name":"opencode.ai.","TTL":294,"type":5,"data":"alias.example."}'
          ']}';
      final ips = DnsBootstrap.parseDohAnswer(body);
      expect(ips.map((e) => e.address), ['172.65.90.21', '172.65.90.20']);
    });

    test('Status 非 0 返回空', () {
      expect(DnsBootstrap.parseDohAnswer('{"Status":3,"Answer":[]}'), isEmpty);
    });

    test('空/非法输入返回空而不抛异常', () {
      expect(DnsBootstrap.parseDohAnswer(null), isEmpty);
      expect(DnsBootstrap.parseDohAnswer(''), isEmpty);
      expect(DnsBootstrap.parseDohAnswer('not json'), isEmpty);
    });
  });

  group('DnsBootstrap.resolve', () {
    late DnsBootstrap dns;

    setUp(() {
      dns = DnsBootstrap.instance;
      dns.resetCache();
      dns.systemLookup = null;
      dns.dohQuery = null;
    });

    tearDown(() {
      dns.resetCache();
      dns.systemLookup = null;
      dns.dohQuery = null;
    });

    test('系统 DNS 成功时不触发 DoH', () async {
      var dohCalled = false;
      dns.systemLookup = (host) async => [InternetAddress('172.65.90.20')];
      dns.dohQuery = (host) async {
        dohCalled = true;
        return '{"Status":0,"Answer":[]}';
      };

      final ips = await dns.resolve('opencode.ai');
      expect(ips.single.address, '172.65.90.20');
      expect(dohCalled, isFalse);
    });

    test('系统 DNS 失败时回退到 DoH', () async {
      dns.systemLookup = (host) async => throw const SocketException('Failed host lookup');
      dns.dohQuery = (host) async =>
          '{"Status":0,"Answer":[{"name":"$host.","type":1,"data":"172.65.90.23"}]}';

      final ips = await dns.resolve('opencode.ai');
      expect(ips.single.address, '172.65.90.23');
    });

    test('全部失败时抛 SocketException', () async {
      dns.systemLookup = (host) async => throw const SocketException('Failed host lookup');
      dns.dohQuery = (host) async => null;

      expect(
        () => dns.resolve('opencode.ai'),
        throwsA(isA<SocketException>()),
      );
    });

    test('结果命中缓存不重复解析', () async {
      var systemCalls = 0;
      dns.systemLookup = (host) async {
        systemCalls++;
        return [InternetAddress('172.65.90.20')];
      };

      await dns.resolve('opencode.ai');
      await dns.resolve('opencode.ai');
      expect(systemCalls, 1);
    });

    test('resolveViaDoH 跳过系统 DNS（污染 IP 场景）', () async {
      final systemCalls = <String>[];
      dns.systemLookup = (host) async {
        systemCalls.add(host);
        return [InternetAddress('203.0.113.1')]; // 假 IP
      };
      dns.dohQuery = (host) async =>
          '{"Status":0,"Answer":[{"name":"$host.","type":1,"data":"172.65.90.20"}]}';

      final ips = await dns.resolveViaDoH('opencode.ai');
      expect(ips.single.address, '172.65.90.20');
      expect(systemCalls, isEmpty);
    });

    test('DoH 查询异常时走负缓存并抛 SocketException', () async {
      dns.systemLookup = (host) async => throw const SocketException('Failed host lookup');
      dns.dohQuery = (host) async => throw const SocketException('doh down');

      expect(
        () => dns.resolve('opencode.ai'),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
