// Maintainable Vehicle Data Repository for Bikes & Scooters

class VehicleData {
  static const List<String> vehicleTypes = ['Bike', 'Scooter'];

  static const List<String> fuelTypes = ['Petrol', 'EV'];

  static const List<String> taxStatuses = [
    'Fully Paid',
    'Need to Pay Tax',
  ];

  static const List<String> bankNames = [
    'Nabil Bank Limited',
    'Nepal Investment Mega Bank Limited',
    'Global IME Bank Limited',
    'Standard Chartered Bank Nepal Limited',
    'Himalayan Bank Limited',
    'Nepal SBI Bank Limited',
    'Everest Bank Limited',
    'NMB Bank Limited',
    'NIC Asia Bank Limited',
    'Kumari Bank Limited',
    'Laxmi Sunrise Bank Limited',
    'Siddhartha Bank Limited',
    'Agricultural Development Bank Limited',
    'Rastriya Banijya Bank Limited',
    'Prime Commercial Bank Limited',
    'Sanima Bank Limited',
    'Citizens Bank International Limited',
    'Prabhu Bank Limited',
    'Machhapuchhre Bank Limited',
    'Other Bank',
  ];

  static const List<String> commonColours = [
    'Black',
    'Matte Black',
    'Red',
    'Blue',
    'White',
    'Silver',
    'Grey',
    'Green',
    'Yellow',
    'Orange',
    'Maroon',
    'Other',
  ];

  // Brand data categorized by Vehicle Type
  static const Map<String, List<String>> _brandsByType = {
    'Bike': [
      'Honda',
      'Yamaha',
      'Bajaj',
      'TVS',
      'Hero',
      'Royal Enfield',
      'KTM',
      'Suzuki',
      'Crossfire',
      'Husqvarna',
      'BMW',
      'Benelli',
      'Ather',
      'Yadea',
      'Revtek',
      'Super Soco',
      'Other',
    ],
    'Scooter': [
      'Honda',
      'Yamaha',
      'TVS',
      'Suzuki',
      'Hero',
      'Vespa',
      'Aprilia',
      'Bajaj',
      'Ather',
      'Yadea',
      'NIU',
      'Segway',
      'Pure EV',
      'Other',
    ],
  };

  // Model datasets indexed by "VehicleType_BrandName"
  static const Map<String, List<String>> _modelsByBrand = {
    // Bikes
    'Bike_Honda': [
      'CB Shine 125',
      'Shine SP',
      'SP 125',
      'Unicorn 160',
      'XR 190L',
      'Hornet 2.0',
      'CBR 250R',
      'CBR 150R',
      'CB350 H\'ness',
      'CRF 300L',
      'Other',
    ],
    'Bike_Yamaha': [
      'FZ-S V3 FI',
      'FZ-FI',
      'R15 V4',
      'R15S',
      'MT-15 V2',
      'FZ-X',
      'FZ 25',
      'Crosser 150',
      'Other',
    ],
    'Bike_Bajaj': [
      'Pulsar 150',
      'Pulsar 220F',
      'Pulsar NS200',
      'Pulsar NS160',
      'Pulsar N160',
      'Pulsar 125',
      'Avenger 220 Cruise',
      'Dominar 400',
      'Dominar 250',
      'Other',
    ],
    'Bike_TVS': [
      'Apache RTR 160 2V',
      'Apache RTR 160 4V',
      'Apache RTR 200 4V',
      'Raider 125',
      'Ronin 225',
      'Star City Plus',
      'Radeon',
      'Other',
    ],
    'Bike_Hero': [
      'Splendor Plus',
      'HF Deluxe',
      'Glamour 125',
      'Super Splendor',
      'Xpulse 200 4V',
      'Xtreme 160R',
      'Karizma XMR',
      'Other',
    ],
    'Bike_Royal Enfield': [
      'Classic 350',
      'Bullet 350',
      'Hunter 350',
      'Meteor 350',
      'Himalayan 450',
      'Scram 411',
      'Interceptor 650',
      'Other',
    ],
    'Bike_KTM': [
      'Duke 200',
      'Duke 250',
      'Duke 390',
      'RC 200',
      'RC 390',
      'Adventure 390',
      'Other',
    ],
    'Bike_Suzuki': [
      'Gixxer 155',
      'Gixxer SF 150',
      'Gixxer 250',
      'Intruder 150',
      'Other',
    ],
    'Bike_Crossfire': [
      'GR7 250',
      'RM 250',
      'Tracker 250',
      'HJ 250',
      'Other',
    ],
    'Bike_Husqvarna': [
      'Svartpilen 250',
      'Vitpilen 250',
      'Other',
    ],
    'Bike_BMW': [
      'G 310 R',
      'G 310 GS',
      'Other',
    ],
    'Bike_Benelli': [
      'TNT 150i',
      'BN 125',
      'TRK 251',
      'Imperial 400',
      'Other',
    ],
    'Bike_Ather': [
      'Apex (EV)',
      '450X (EV)',
      'Other',
    ],
    'Bike_Yadea': [
      'Keeness (EV)',
      'G5 (EV)',
      'Other',
    ],

    // Scooters
    'Scooter_Honda': [
      'Activa 6G',
      'Activa 125',
      'Dio',
      'Dio 125',
      'Grazia 125',
      'Aviator',
      'Other',
    ],
    'Scooter_Yamaha': [
      'RayZR 125 FI',
      'Fascino 125 FI',
      'Aerox 155',
      'Ray Z',
      'Other',
    ],
    'Scooter_TVS': [
      'Ntorq 125',
      'Ntorq Race Edition',
      'Jupiter 110',
      'Jupiter 125',
      'Zest 110',
      'iQube (EV)',
      'Other',
    ],
    'Scooter_Suzuki': [
      'Access 125',
      'Burgman Street 125',
      'Avenis 125',
      'Swish',
      'Other',
    ],
    'Scooter_Hero': [
      'Pleasure Plus',
      'Maestro Edge 125',
      'Destini 125',
      'Vida V1 Pro (EV)',
      'Other',
    ],
    'Scooter_Vespa': [
      'LX 125',
      'VXL 150',
      'SXL 150',
      'Elegante 150',
      'ZX 125',
      'Other',
    ],
    'Scooter_Aprilia': [
      'SR 125',
      'SR 160',
      'SXR 160',
      'Storm 125',
      'Other',
    ],
    'Scooter_Bajaj': [
      'Chetak Premium (EV)',
      'Chetak Urbane (EV)',
      'Other',
    ],
    'Scooter_Ather': [
      '450X (EV)',
      '450S (EV)',
      'Rizta (EV)',
      'Other',
    ],
    'Scooter_Yadea': [
      'G5 (EV)',
      'T9 (EV)',
      'C1S (EV)',
      'Other',
    ],
    'Scooter_NIU': [
      'NQi GT (EV)',
      'MQi+ Sport (EV)',
      'NGT (EV)',
      'Other',
    ],
    'Scooter_Segway': [
      'Ninebot E110L (EV)',
      'Ninebot E125S (EV)',
      'Other',
    ],
    'Scooter_Pure EV': [
      'EPluto 7G (EV)',
      'ETrance Neo (EV)',
      'Other',
    ],
  };

  /// Get available brands for selected vehicle type
  static List<String> getBrandsForType(String vehicleType) {
    return _brandsByType[vehicleType] ?? ['Honda', 'Yamaha', 'Bajaj', 'TVS', 'Hero', 'Other'];
  }

  /// Get available models for selected vehicle type and brand
  static List<String> getModelsForBrand(String vehicleType, String brand) {
    final key = '${vehicleType}_$brand';
    return _modelsByBrand[key] ?? ['Standard Model', 'Other'];
  }
}
