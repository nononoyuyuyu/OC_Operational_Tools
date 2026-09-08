import 'package:flutter/material.dart';
import 'tool_activity.dart';
import 'tool_status.dart';

abstract interface class ToolModule {
  String get id;
  String get title;
  String get description;
  IconData get icon;
  Listenable get changes;
  String get status;
  bool get connected;
  bool get busy;
  ToolConnection? get connection;
  ToolFeedback? get feedback;
  List<ToolActivity> get activities;

  /// 有限の幅・高さを受け取る作業画面。スクロールは各ツール内で管理する。
  Widget buildPage();
  Widget buildSettings();
  Widget buildActivityFeedback();

  /// 有限の幅・高さを受け取る履歴詳細。ページ送りはツール内で管理する。
  Widget buildActivityDetails(String id);
  Future<void> initialize();
  void dispose();
}

/// 履歴を必要な分だけ取得するツールの追加機能。
/// activitiesは日時降順（同時刻はID昇順）の先頭から連続して取得し、末尾へ追加する。
abstract interface class PagedActivityModule {
  int get activityTotal;
  bool get hasMoreActivities;
  Future<void> loadMoreActivities();
}
