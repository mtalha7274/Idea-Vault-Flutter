import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/utils/selection_controller.dart';

void main() {
  group('SelectionController', () {
    late SelectionController controller;
    late int notifications;

    setUp(() {
      controller = SelectionController();
      notifications = 0;
      controller.addListener(() => notifications += 1);
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts inactive', () {
      expect(controller.isActive, isFalse);
      expect(controller.count, 0);
      expect(controller.selectedIds, isEmpty);
    });

    test('select enters selection and ignores repeats', () {
      controller.select('a');
      controller.select('a');

      expect(controller.isActive, isTrue);
      expect(controller.isSelected('a'), isTrue);
      expect(notifications, 1);
    });

    test('toggle adds and removes, and the last removal exits', () {
      controller.toggle('a');
      controller.toggle('b');
      expect(controller.count, 2);

      controller.toggle('a');
      expect(controller.selectedIds, {'b'});

      controller.toggle('b');
      expect(controller.isActive, isFalse);
      expect(notifications, 4);
    });

    test('selectAll adds every id and containsAll reports it', () {
      controller.select('a');
      controller.selectAll(['a', 'b', 'c']);

      expect(controller.selectedIds, {'a', 'b', 'c'});
      expect(controller.containsAll(['a', 'b', 'c']), isTrue);
      expect(controller.containsAll(['a', 'd']), isFalse);
      expect(notifications, 2);

      controller.selectAll(['a', 'b']);
      expect(notifications, 2);
    });

    test('selectAll handles hundreds of ids', () {
      final ids = List<String>.generate(500, (index) => 'id-$index');

      controller.selectAll(ids);

      expect(controller.count, 500);
      expect(notifications, 1);
    });

    test('clear exits and only notifies when something was selected', () {
      controller.clear();
      expect(notifications, 0);

      controller.selectAll(['a', 'b']);
      controller.clear();

      expect(controller.isActive, isFalse);
      expect(notifications, 2);
    });

    test('retainExisting drops ids that no longer exist', () {
      controller.selectAll(['a', 'b', 'c']);

      controller.retainExisting(['b', 'c', 'd']);
      expect(controller.selectedIds, {'b', 'c'});
      expect(notifications, 2);

      controller.retainExisting(['b', 'c']);
      expect(notifications, 2);

      controller.retainExisting(const []);
      expect(controller.isActive, isFalse);
      expect(notifications, 3);
    });

    test('deselectAll removes only the given ids', () {
      controller.selectAll(['a', 'b', 'c']);

      controller.deselectAll(['a', 'z']);

      expect(controller.selectedIds, {'b', 'c'});
    });

    test('selectedIds cannot be mutated from outside', () {
      controller.select('a');

      expect(() => controller.selectedIds.add('b'), throwsUnsupportedError);
    });
  });
}
