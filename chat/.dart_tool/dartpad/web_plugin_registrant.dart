// Flutter web plugin registrant file.
//
// Generated file. Do not edit.
//

// @dart = 2.13
// ignore_for_file: type=lint

import 'package:app_links_web/app_links_web.dart';
import 'package:audio_session/audio_session_web.dart';
import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:flutter_blue_plus_web/flutter_blue_plus_web.dart';
import 'package:flutter_gemma/web/flutter_gemma_web.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:just_audio_web/just_audio_web.dart';
import 'package:opus_flutter_web/opus_flutter_web.dart';
import 'package:package_info_plus/src/package_info_plus_web.dart';
import 'package:permission_handler_html/permission_handler_html.dart';
import 'package:record_web/record_web.dart';
import 'package:sentry_flutter/sentry_flutter_web.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
import 'package:wakelock_plus/src/wakelock_plus_web_plugin.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
  AppLinksPluginWeb.registerWith(registrar);
  AudioSessionWeb.registerWith(registrar);
  FilePickerWeb.registerWith(registrar);
  FlutterBluePlusWeb.registerWith(registrar);
  FlutterGemmaWeb.registerWith(registrar);
  FlutterSecureStorageWeb.registerWith(registrar);
  JustAudioPlugin.registerWith(registrar);
  OpusFlutterWeb.registerWith(registrar);
  PackageInfoPlusWebPlugin.registerWith(registrar);
  WebPermissionHandler.registerWith(registrar);
  RecordPluginWeb.registerWith(registrar);
  SentryFlutterWeb.registerWith(registrar);
  SharedPreferencesPlugin.registerWith(registrar);
  UrlLauncherPlugin.registerWith(registrar);
  WakelockPlusWebPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
