import 'package:cloud_functions/cloud_functions.dart';

class IdeaOrganizationRepository {
  const IdeaOrganizationRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<String> organizeIdea(String sectionContent) async {
    try {
      final callable = _functions.httpsCallable('organizeSection');
      final response = await callable.call({'sectionContent': sectionContent});
      return (response.data as Map)['organizedContent'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to organize idea: ${e.message}');
    } catch (e) {
      throw Exception('Failed to organize idea: $e');
    }
  }
}
