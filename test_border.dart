import 'package:flutter/material.dart';
class TestBorder extends OutlinedBorder {
  const TestBorder({super.side = BorderSide.none});
  @override
  OutlinedBorder copyWith({BorderSide? side}) => TestBorder(side: side ?? this.side);
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  @override
  ShapeBorder scale(double t) => TestBorder(side: side.scale(t));
}
