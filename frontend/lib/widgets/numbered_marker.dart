import 'package:flutter/material.dart';

/// 帶數字的圓形地標，用於行程中的景點順序（Phase 2 起）。
class NumberedMarker extends StatelessWidget {
  final int number;
  final Color color;

  const NumberedMarker({super.key, required this.number, this.color = Colors.deepOrange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

/// 起點／終點用的圓點標記。
class EndpointMarker extends StatelessWidget {
  final IconData icon;
  final Color color;

  const EndpointMarker({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}
