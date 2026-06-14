class AssetPaths {
  static const logos = _Logos();
  static const icons = _Icons();
  static const effects = _Effects();
  static const diagrams = _Diagrams();
}

class _Logos {
  const _Logos();

  final kinexaDark = 'assets/logos/kinexa_logo_dark.svg';
  final kinexaDarkInv = 'assets/logos/kinexa_logo_dark_inv.svg';
  final kinexaWhite = 'assets/logos/kinexa_logo_white.svg';
  final iconDark = 'assets/logos/kinexa_icon_dark.svg';
  final iconRed = 'assets/logos/kinexa_icon_red.svg';
  final iconWhite = 'assets/logos/kinexa_icon_white.svg';
  final sesi = 'assets/logos/sesi_logo.svg';
  final sesiPng = 'assets/logos/partner_sesi.png';
  final einstein = 'assets/logos/einstein_logo.svg';
  final einsteinPng = 'assets/logos/partner_einstein.png';
}

class _Icons {
  const _Icons();

  final device = 'assets/icons/device.svg';
  final phone = 'assets/icons/phone.svg';
}

class _Effects {
  const _Effects();

  final radarBase = 'assets/effects/radar_base.svg';
  final radarGrid = 'assets/effects/radar_grid.svg';
  final radarSweeper = 'assets/effects/radar_sweeper.svg';
}

class _Diagrams {
  const _Diagrams();

  final deviceOrientation = 'assets/diagrams/device_orientation.svg';
  final footOrientation = 'assets/diagrams/foot_orientation.svg';
}
