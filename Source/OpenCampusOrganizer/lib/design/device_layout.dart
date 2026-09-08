import 'package:flutter/material.dart';

/// 縦横の回転で機能を入れ替えず、狭いPCウィンドウでもPCの機能を保つ。
bool isPhoneLayout(BuildContext context) =>
    (Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS) &&
    MediaQuery.sizeOf(context).shortestSide < 600;
