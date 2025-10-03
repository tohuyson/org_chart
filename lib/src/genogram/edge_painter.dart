import 'dart:math';

import 'package:flutter/material.dart';
import 'package:org_chart/src/base/edge_painter_utils.dart';
import 'package:org_chart/src/genogram/genogram_enums.dart';
import 'package:org_chart/src/common/node.dart';
import 'package:org_chart/src/base/base_controller.dart';
import 'package:org_chart/src/genogram/genogram_controller.dart';
import 'package:org_chart/src/genogram/genogram_edge_config.dart';

/// Connection points on a node
enum ConnectionPoint {
  top,
  right,
  bottom,
  left,
  center,
}

/// Relationship type in a genogram
enum RelationshipType {
  marriage,
  parent,
  child,
}

/// A highly customizable painter for genogram edges
class GenogramEdgePainter<E> extends CustomPainter {
  final GenogramController<E> controller;

  final EdgePainterUtils utils;

  /// Configuration for edge styling
  final GenogramEdgeConfig config;

  /// Function to get marriage status for a relationship (defaults to married)
  final MarriageStatus Function(E person, E spouse)? marriageStatusProvider;
  // Maps to track marriage connections
  final Map<String, Color> _marriageColors = {};
  final Map<String, Offset> _marriagePoints = {};

  GenogramEdgePainter({
    required this.controller,
    required Paint linePaint,
    double cornerRadius = 15,
    required GraphArrowStyle arrowStyle,
    LineEndingType lineEndingType = LineEndingType.none,
    this.config = const GenogramEdgeConfig(),
    this.marriageStatusProvider,
  }) : utils = EdgePainterUtils(
          linePaint: linePaint,
          cornerRadius: cornerRadius,
          arrowStyle: arrowStyle,
          lineEndingType: lineEndingType,
        );

  @override
  void paint(Canvas canvas, Size size) {
    // Clear tracking maps for new painting cycle
    _marriageColors.clear();
    _marriagePoints.clear();

    final List<Node<E>> allNodes = controller.nodes;

    // First pass: Draw marriage connections
    _drawMarriageConnections(canvas, allNodes);

    // Second pass: Draw parent-child connections
    _drawParentChildConnections(canvas, allNodes);
  }

  /// Draw marriage connections between spouses
  void _drawMarriageConnections(Canvas canvas, List<Node<E>> nodes) {
    // First collect all marriages to properly index colors
    final marriages = <Map<String, dynamic>>[];

    // Collect marriages
    for (final Node<E> person in nodes) {
      final String personId = controller.idProvider(person.data);
      final List<String>? spouses = controller.spousesProvider(person.data);

      // Skip if no spouses
      if (spouses == null || spouses.isEmpty) continue;

      // Only process marriages from males to avoid duplication
      if (!controller.isMale(person.data)) continue;

      for (int i = 0; i < spouses.length; i++) {
        final String spouseId = spouses[i];

        // Find spouse node
        Node<E>? spouse;
        try {
          spouse = nodes.firstWhere(
            (node) => controller.idProvider(node.data) == spouseId,
          );
        } catch (_) {
          continue; // Spouse not found
        }

        // Add to marriages collection
        marriages.add({
          'husband': person,
          'wife': spouse,
          'spouseIndex': i,
          'marriageKey': '$personId|$spouseId',
        });
      }
    }

    // Sort marriages to ensure consistent color assignment
    marriages.sort((a, b) => a['marriageKey'].compareTo(b['marriageKey']));

    // Assign colors and draw marriages
    for (int i = 0; i < marriages.length; i++) {
      final marriage = marriages[i];
      final Node<E> husband = marriage['husband'];
      final Node<E> wife = marriage['wife'];
      final int spouseIndex = marriage['spouseIndex'];
      final String marriageKey = marriage['marriageKey']; // Assign color
      final Color marriageColor =
          config.marriageColors[i % config.marriageColors.length];
      _marriageColors[marriageKey] = marriageColor;

      // Get connection points
      final Offset husbandConn =
          _getConnectionPoint(husband, ConnectionPoint.right);
      final Offset wifeConn = _getConnectionPoint(wife, ConnectionPoint.left);

      // Apply offset for multiple marriages
      final double offset = 0; //-5.0 * spouseIndex;
      final Offset husbandOffset, wifeOffset;

      if (controller.orientation == GraphOrientation.topToBottom) {
        husbandOffset = husbandConn.translate(0, offset);
        wifeOffset = wifeConn.translate(0, offset);
      } else {
        husbandOffset = husbandConn.translate(offset, 0);
        wifeOffset = wifeConn.translate(offset, 0);
      } // Determine marriage status if provider exists
      MarriageStatus status = MarriageStatus.married;
      if (marriageStatusProvider != null) {
        status = marriageStatusProvider!(husband.data, wife.data);
      }

      // Get the appropriate marriage style for this status
      final marriageStyle = config.getMarriageStyle(status);
      final double strokeWidth = marriageStyle.lineStyle.strokeWidth;

      // Create custom paint for this marriage
      final Paint marriagePaint = Paint()
        ..color = marriageColor
        ..strokeWidth = marriageStyle.lineStyle.strokeWidth
        ..style = marriageStyle.lineStyle.paintStyle;

      // Draw the marriage line
      // canvas.drawLine(husbandOffset, wifeOffset, marriagePaint);

      final husbandOffsetNew = husbandOffset.translate(0, 24);
      final wifeOffsetNew = wifeOffset.translate(0, 24);
      canvas.drawLine(husbandOffset, husbandOffsetNew, marriagePaint);
      canvas.drawLine(wifeOffset, wifeOffsetNew, marriagePaint);

      canvas.drawLine(husbandOffsetNew.translate(-strokeWidth / 2, 0),
          wifeOffsetNew.translate(strokeWidth / 2, 0), marriagePaint);

      final double r = 16;
      final center = Offset(
          husbandOffsetNew.dx + (wifeOffsetNew.dx - husbandOffsetNew.dx) / 2,
          husbandOffsetNew.dy);
      final path = Path()
        ..moveTo(center.dx + r * cos(0), center.dy + r * sin(0)) // phải
        ..lineTo(
            center.dx + r * cos(pi / 2), center.dy + r * sin(pi / 2)) // dưới
        ..lineTo(center.dx + r * cos(pi), center.dy + r * sin(pi)) // trái
        ..lineTo(center.dx + r * cos(3 * pi / 2),
            center.dy + r * sin(3 * pi / 2)) // trên
        ..close();

      final paint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);

      // Calculate connection point based on spouse index
      // For first spouse (index 0): use midpoint (ratio 0.5)
      // For additional spouses: move closer to wife (ratio > 0.5)
      double connectionRatio = spouseIndex == 0 ? 0.5 : 0.9;

      // Store the weighted point for child connections
      _marriagePoints[marriageKey] = Offset(
          husbandOffsetNew.dx +
              (wifeOffsetNew.dx - husbandOffsetNew.dx) * connectionRatio,
          husbandOffsetNew.dy +
              r * 0.95 +
              (wifeOffsetNew.dy - husbandOffsetNew.dy) * connectionRatio);
    }
  }

  /// Draw connections between parents and children
  void _drawParentChildConnections(Canvas canvas, List<Node<E>> nodes) {
    String makeMarriageKey(String id1, String id2) {
      // luôn sắp xếp để key đồng nhất
      // final sorted = [id1, id2]..sort();
      // return '${sorted[0]}|${sorted[1]}';
      return '$id1|$id2';
    }

    for (final Node<E> child in nodes) {
      // Get parent IDs
      final List<String> fatherIds =
          controller.fatherProvider(child.data) ?? [];
      final List<String> motherIds =
          controller.motherProvider(child.data) ?? [];

      // Skip if no parent info
      if (fatherIds.isEmpty && motherIds.isEmpty) continue;

      // Find parent nodes
      List<Node<E>> fathers = [], mothers = [];

      if (fatherIds.isNotEmpty) {
        try {
          fathers = nodes
              .where((node) =>
                  fatherIds.contains(controller.idProvider(node.data)))
              .toList();
        } catch (_) {
          fathers = [];
        }
      }

      if (motherIds.isNotEmpty) {
        try {
          mothers = nodes
              .where((node) =>
                  motherIds.contains(controller.idProvider(node.data)))
              .toList();
        } catch (_) {
          mothers = [];
        }
      }

      // Get connection point on child
      final Offset childConn = _getConnectionPoint(
          child, ConnectionPoint.top); // Special case for married female
      // final bool isMarriedFemale = controller.isFemale(child.data) &&
      //     controller.getSpouseList(child.data).isNotEmpty;

      // track những parent đã được nối qua marriage
      final Set<String> usedParents = {};

      // Different cases of parent-child connections
      if (fathers.isNotEmpty && mothers.isNotEmpty) {
        for (final father in fathers) {
          for (final mother in mothers) {
            final marriageKey = makeMarriageKey(
              controller.idProvider(father.data),
              controller.idProvider(mother.data),
            );

            if (_marriagePoints.containsKey(marriageKey)) {
              usedParents.add(controller.idProvider(father.data));
              usedParents.add(controller.idProvider(mother.data));

              final marriagePoint = _marriagePoints[marriageKey]!;
              final marriageColor = _marriageColors[marriageKey] ?? Colors.grey;

              final connectionPaint = Paint()
                ..color = marriageColor
                ..strokeWidth = config.childStrokeWidth
                ..style = PaintingStyle.stroke;

              // final connectionType = isMarriedFemale
              //     ? ConnectionType.twoSegment
              //     : ConnectionType.genogramParentChild;

              final connectionType = ConnectionType.genogramParentChild;

              utils.drawConnection(
                canvas,
                marriagePoint,
                childConn,
                controller.boxSize,
                controller.orientation,
                type: connectionType,
                paint: connectionPaint,
              );
            }
          }
        }
      }

      // Nối những cha không nằm trong marriage nào
      for (final father in fathers) {
        if (!usedParents.contains(controller.idProvider(father.data))) {
          // _drawSingleParentConnection(canvas, father, child, isMarriedFemale);
          _drawSingleParentConnection(canvas, father, child, false);
        }
      }

      // Nối những mẹ không nằm trong marriage nào
      for (final mother in mothers) {
        if (!usedParents.contains(controller.idProvider(mother.data))) {
          // _drawSingleParentConnection(canvas, mother, child, isMarriedFemale);
          _drawSingleParentConnection(canvas, mother, child, false);
        }
      }
    }
  }

  /// Draw a connection between a single parent and child
  void _drawSingleParentConnection(
      Canvas canvas, Node<E> parent, Node<E> child, bool isMarriedFemale) {
    final Paint parentPaint = Paint()
      ..color = config.childSingleParentColor
      ..strokeWidth = config.childSingleParentStrokeWidth
      ..style = PaintingStyle.stroke;

    final Offset parentConn =
        _getConnectionPoint(parent, ConnectionPoint.bottom);
    final Offset childConn = _getConnectionPoint(child, ConnectionPoint.top);

    final connectionType =
        isMarriedFemale ? ConnectionType.twoSegment : ConnectionType.direct;

    // final connectionType = ConnectionType.twoSegment;

    utils.drawConnection(canvas, parentConn, childConn, controller.boxSize,
        controller.orientation,
        type: connectionType, paint: parentPaint);
  }

  /// Get connection point on a node based on location
  Offset _getConnectionPoint(Node<E> node, ConnectionPoint point) {
    switch (point) {
      case ConnectionPoint.top:
        return node.position + Offset(controller.boxSize.width / 2, 0);
      case ConnectionPoint.right:
        return node.position +
            Offset(controller.boxSize.width / 2, controller.boxSize.height);
      case ConnectionPoint.bottom:
        return node.position +
            Offset(controller.boxSize.width / 2, controller.boxSize.height);
      case ConnectionPoint.left:
        return node.position +
            Offset(controller.boxSize.width / 2, controller.boxSize.height);
      case ConnectionPoint.center:
        return node.position +
            Offset(controller.boxSize.width / 2, controller.boxSize.height / 2);
    }
  }

  @override
  bool shouldRepaint(covariant GenogramEdgePainter<E> oldDelegate) {
    // Only repaint if the controller, configs, or paint properties have changed
    return oldDelegate.controller != controller ||
        oldDelegate.config != config ||
        oldDelegate.marriageStatusProvider != marriageStatusProvider ||
        oldDelegate.utils.linePaint != utils.linePaint ||
        oldDelegate.utils.cornerRadius != utils.cornerRadius ||
        oldDelegate.utils.arrowStyle != utils.arrowStyle ||
        oldDelegate.utils.lineEndingType != utils.lineEndingType;
  }
}
