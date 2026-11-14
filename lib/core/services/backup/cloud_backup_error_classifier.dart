import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../../models/backup/cloud_backup_error.dart';

class CloudBackupErrorClassifier {
  const CloudBackupErrorClassifier._();

  static const String iCloudUnavailableCode = 'E_CTR';
  static const String iCloudFileNotFoundCode = 'E_FNF';

  static CloudBackupErrorType classify(Object error) {
    if (error is CloudBackupException) {
      return error.type;
    }
    if (error is TimeoutException) {
      return CloudBackupErrorType.timeout;
    }
    if (error is SocketException ||
        error is HttpException ||
        error is http.ClientException) {
      return CloudBackupErrorType.offline;
    }
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return CloudBackupErrorType.signInCancelled;
        default:
          return CloudBackupErrorType.signInRequired;
      }
    }
    if (error is drive.DetailedApiRequestError) {
      final status = error.status;
      if (status == 401 || status == 403) {
        return CloudBackupErrorType.signInRequired;
      }
      if (status == 404) {
        return CloudBackupErrorType.noBackupFound;
      }
      return CloudBackupErrorType.unknown;
    }
    if (error is PlatformException) {
      if (error.code == iCloudUnavailableCode) {
        return CloudBackupErrorType.iCloudUnavailable;
      }
      if (error.code == iCloudFileNotFoundCode) {
        return CloudBackupErrorType.noBackupFound;
      }
      final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (message.contains('network') || message.contains('offline')) {
        return CloudBackupErrorType.offline;
      }
      return CloudBackupErrorType.unknown;
    }
    return CloudBackupErrorType.unknown;
  }
}
