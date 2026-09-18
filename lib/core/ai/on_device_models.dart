import 'package:flutter_gemma/flutter_gemma.dart';

/// A curated Gemma model that can be downloaded once and then run fully
/// on-device, offline. URLs/filenames are the canonical LiteRT-LM builds.
/// flutter_gemma keys installed models by their filename, so [id] must equal
/// the URL's basename.
class OnDeviceModel {
  const OnDeviceModel({
    required this.id,
    required this.url,
    required this.displayName,
    required this.sizeLabel,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.needsAuth = false,
    this.supportsVision = false,
    this.note,
  });

  final String id;
  final String url;
  final String displayName;
  final String sizeLabel;
  final ModelType modelType;
  final ModelFileType fileType;

  /// Gated on Hugging Face — needs an accepted license + access token.
  final bool needsAuth;

  /// Multimodal (can read receipt images).
  final bool supportsVision;

  final String? note;
}

/// Models offered for on-device inference.
///
/// All are **non-gated** — they download from the public `litert-community`
/// repos with NO Hugging Face token. Gemma 4 (E2B/E4B) is the powerful,
/// token-free option the user asked for, shipped as `.litertlm` (LiteRT-LM).
const List<OnDeviceModel> kOnDeviceModels = [
  OnDeviceModel(
    id: 'gemma-4-E2B-it.litertlm',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    displayName: 'Gemma 4 E2B',
    sizeLabel: '~2.4 GB',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    supportsVision: true,
    note: 'Potente y sin token. Multimodal. Recomendado para gama media/alta.',
  ),
  OnDeviceModel(
    id: 'gemma-4-E4B-it.litertlm',
    url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    displayName: 'Gemma 4 E4B',
    sizeLabel: '~4.3 GB',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    supportsVision: true,
    note: 'El más capaz, sin token. Necesita bastante RAM (gama alta).',
  ),
];

OnDeviceModel? onDeviceModelById(String id) {
  for (final m in kOnDeviceModels) {
    if (m.id == id) return m;
  }
  return null;
}
