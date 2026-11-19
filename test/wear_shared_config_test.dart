import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/core/kreta_auth_config.dart';

void main() {
  test('shared/kreta_config.json stays in exact sync with Dart KretaAuthConfig and KretaEndpoints', () {
    final configFile = File('shared/kreta_config.json');
    expect(configFile.existsSync(), isTrue);

    final json = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    expect(json['idpBaseUrl'], KretaAuthConfig.idpBaseUrl);
    expect(json['authorizeEndpoint'], KretaAuthConfig.authorizeEndpoint);
    expect(json['loginEndpoint'], KretaAuthConfig.loginEndpoint);
    expect(json['tokenEndpoint'], KretaAuthConfig.tokenEndpoint);
    expect(json['clientIdIos'], KretaAuthConfig.clientIdIos);
    expect(json['clientIdAndroid'], KretaAuthConfig.clientIdAndroid);
    expect(json['redirectUri'], KretaAuthConfig.redirectUri);
    expect(json['scopes'], KretaAuthConfig.scopes);
    expect(json['userAgent'], KretaAuthConfig.userAgent);
    expect(json['apiKey'], KretaAuthConfig.apiKey);
    expect(json['kretaBaseDomain'], KretaEndpoints.kretaBase);

    final endpoints = json['endpoints'] as Map<String, dynamic>;
    const sampleIss = 'klik035220001';
    expect(
      KretaEndpoints.getTimeTable(sampleIss),
      'https://$sampleIss.${KretaEndpoints.kretaBase}${endpoints['timetable']}',
    );
    expect(
      KretaEndpoints.getGrades(sampleIss),
      'https://$sampleIss.${KretaEndpoints.kretaBase}${endpoints['grades']}',
    );
    expect(
      KretaEndpoints.getHomework(sampleIss),
      'https://$sampleIss.${KretaEndpoints.kretaBase}${endpoints['homeworks']}',
    );
    expect(
      KretaEndpoints.getStudent(sampleIss),
      'https://$sampleIss.${KretaEndpoints.kretaBase}${endpoints['student']}',
    );
    expect(endpoints['tests'], '/ellenorzo/v3/sajat/BejelentettSzamonkeresek');

    final wearRelay = json['wearRelay'] as Map<String, dynamic>;
    expect(wearRelay['deepLinkScheme'], 'tintanaplo');
    expect(wearRelay['deepLinkHost'], 'wear-auth');
    expect(wearRelay['deepLinkUri'], 'tintanaplo://wear-auth');
    expect(wearRelay['messagePathRequestAuth'], '/tinta/request_auth');
    expect(wearRelay['dataPathAuthSession'], '/tinta/auth_session');
    expect(wearRelay['dataPathDashboardSync'], '/tinta/dashboard_sync');
  });
}
