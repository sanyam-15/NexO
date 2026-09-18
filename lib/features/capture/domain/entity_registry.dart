/// Catalog of Mexican financial entities whose Android notifications Nexo can
/// auto-capture. Each entity maps one or more app package names to a display
/// name and a regulatory [EntityType]. Capture is opt-in: the catalog ships
/// fully disabled and the user enables the apps they actually have.
///
/// Many entities ship several apps (wallet vs merchant/TPV vs business);
/// [excludePackages] keeps the wrong one (e.g. a point-of-sale app) from being
/// matched as the personal-finance source.
library;

/// Regulatory class of a financial entity in Mexico. Determines how the
/// captured movement is labelled and, later, how templates are learned.
enum EntityType {
  banco,
  neobanco,
  sofipo,
  ifpe, // Institución de Fondos de Pago Electrónico (Ley Fintech)
  itf, // Institución de Tecnología Financiera
  socap, // cooperativa de ahorro y préstamo
  sofom,
  casaBolsa,
}

extension EntityTypeLabel on EntityType {
  String get label => switch (this) {
        EntityType.banco => 'Banco',
        EntityType.neobanco => 'Neobanco',
        EntityType.sofipo => 'SOFIPO',
        EntityType.ifpe => 'Fintech (IFPE)',
        EntityType.itf => 'Fintech (ITF)',
        EntityType.socap => 'Cooperativa',
        EntityType.sofom => 'SOFOM',
        EntityType.casaBolsa => 'Casa de bolsa',
      };
}

/// A financial entity and the package(s) whose notifications represent it.
class CaptureEntity {
  const CaptureEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.packages,
    this.excludePackages = const [],
  });

  /// Stable identifier used in storage/allowlist (independent of display name).
  final String id;

  /// Short display name that becomes the movement's account, e.g. "Nu", "BBVA".
  final String name;

  final EntityType type;

  /// Android application ids that, when they post a notification, mean money
  /// moved on this entity.
  final List<String> packages;

  /// Sibling package ids that belong to the same brand but are NOT the personal
  /// wallet (merchant/TPV/business apps), so they must never match.
  final List<String> excludePackages;
}

/// Verified v1 allowlist of Mexican banks, neobanks, SOFIPOs and Ley-Fintech
/// IFPEs. Package names are the canonical Play Store application ids.
const List<CaptureEntity> kCaptureEntities = [
  CaptureEntity(
    id: 'nu',
    name: 'Nu',
    type: EntityType.sofipo,
    packages: ['com.nu.production'],
  ),
  CaptureEntity(
    id: 'bbva',
    name: 'BBVA',
    type: EntityType.banco,
    packages: ['com.bancomer.mbanking'],
  ),
  CaptureEntity(
    id: 'mercadopago',
    name: 'Mercado Pago',
    type: EntityType.ifpe,
    packages: ['com.mercadopago.wallet'],
    // The seller/point-of-sale app must not be captured as personal spending.
    excludePackages: ['com.mercadolibre'],
  ),
  CaptureEntity(
    id: 'banamex',
    name: 'Banamex',
    type: EntityType.banco,
    packages: ['com.citibanamex.banamexmobile'],
  ),
  CaptureEntity(
    id: 'klar',
    name: 'Klar',
    type: EntityType.sofipo,
    packages: ['mx.klar.app'],
  ),
  CaptureEntity(
    id: 'stori',
    name: 'Stori',
    type: EntityType.sofipo,
    packages: ['ai.powerup.stori'],
  ),
  CaptureEntity(
    id: 'albo',
    name: 'albo',
    type: EntityType.ifpe,
    packages: ['mx.intelifin.android.albo'],
  ),
  CaptureEntity(
    id: 'spin',
    name: 'Spin by OXXO',
    type: EntityType.ifpe,
    packages: ['com.pagopopmobile'],
  ),
  CaptureEntity(
    id: 'banco_azteca',
    name: 'Banco Azteca',
    type: EntityType.banco,
    packages: ['mx.com.bancoazteca.bazdigitalmovil'],
  ),
  CaptureEntity(
    id: 'bancoppel',
    name: 'BanCoppel',
    type: EntityType.banco,
    packages: ['mx.com.miapp'],
  ),
  CaptureEntity(
    id: 'uala',
    name: 'Ualá',
    type: EntityType.banco,
    packages: ['ar.com.bancar.uala'],
  ),
  CaptureEntity(
    id: 'didi',
    name: 'DiDi',
    type: EntityType.ifpe,
    packages: ['com.didiglobal.passenger'],
  ),
  CaptureEntity(
    id: 'hey_banco',
    name: 'Hey Banco',
    type: EntityType.banco,
    packages: ['mx.heybanco.app', 'mx.heybanco.mobile'],
  ),
  CaptureEntity(
    id: 'santander',
    name: 'Santander',
    type: EntityType.banco,
    packages: ['com.santander.app', 'com.bsmovil.santander'],
  ),
  CaptureEntity(
    id: 'banorte',
    name: 'Banorte',
    type: EntityType.banco,
    packages: ['mx.com.banorte.movilbi', 'com.banorte.bmovil'],
  ),
];

/// Looks up the entity that owns [packageName], honouring [excludePackages].
/// Returns null for unknown / explicitly-excluded packages.
CaptureEntity? entityForPackage(String packageName) {
  final pkg = packageName.trim();
  if (pkg.isEmpty) return null;
  for (final e in kCaptureEntities) {
    if (e.excludePackages.contains(pkg)) return null;
    if (e.packages.contains(pkg)) return e;
  }
  return null;
}

CaptureEntity? entityById(String id) {
  for (final e in kCaptureEntities) {
    if (e.id == id) return e;
  }
  return null;
}

/// Every package the listener should be allowed to observe (the full catalog),
/// used to seed the native allowlist filter.
List<String> get allCatalogPackages =>
    [for (final e in kCaptureEntities) ...e.packages];
