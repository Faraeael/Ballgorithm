/// Fictional name and team corpus for Milestone 001.
///
/// All entries are invented. No real league, team or player branding.
library;

const List<String> firstNames = [
  'Adrian',
  'Alonso',
  'Andrei',
  'Bastian',
  'Caleb',
  'Cassius',
  'Dante',
  'Dario',
  'Elias',
  'Emeka',
  'Emil',
  'Fabricio',
  'Felix',
  'Gideon',
  'Hakim',
  'Hugo',
  'Ilya',
  'Isandro',
  'Jalen',
  'Jonas',
  'Kai',
  'Kasimir',
  'Kellan',
  'Lars',
  'Leandro',
  'Luca',
  'Malik',
  'Mateo',
  'Milo',
  'Nadir',
  'Nikolai',
  'Oren',
  'Pavel',
  'Quentin',
  'Rafael',
  'Ravi',
  'Silas',
  'Tavi',
  'Teodor',
  'Yusuf',
];

const List<String> lastNames = [
  'Abernathy',
  'Ashford',
  'Barlow',
  'Beaumont',
  'Bellamy',
  'Calloway',
  'Castellan',
  'Cortez',
  'Delacroix',
  'Dunmore',
  'Eastwick',
  'Ferrante',
  'Fairweather',
  'Gallardo',
  'Grimsby',
  'Halloran',
  'Hargrove',
  'Ibarra',
  'Jansen',
  'Kestrel',
  'Kovacs',
  'Larkspur',
  'Lindqvist',
  'Marchetti',
  'Merriweather',
  'Nakamura',
  'Okonkwo',
  'Ortega',
  'Pellegrini',
  'Quintero',
  'Rasmussen',
  'Ravensworth',
  'Sandoval',
  'Sinclair',
  'Thackeray',
  'Valdez',
  'Vasquez',
  'Whitlock',
  'Yarrow',
  'Zeller',
];

/// Number of distinct first/last name pairs the corpus can supply. Player
/// generation must not request more unique players than this.
int get namePairCapacity => firstNames.length * lastNames.length;

/// Fixed team catalog. Ids are positional and stable.
const List<TeamSeed> teamCatalog = [
  TeamSeed(id: 'team-1', name: 'Aurora Comets', abbreviation: 'AUR'),
  TeamSeed(id: 'team-2', name: 'Ironvale Forge', abbreviation: 'IRV'),
  TeamSeed(id: 'team-3', name: 'Port Meridian Tides', abbreviation: 'PMT'),
  TeamSeed(id: 'team-4', name: 'Redstone Coyotes', abbreviation: 'RSC'),
  TeamSeed(id: 'team-5', name: 'Northgate Lynx', abbreviation: 'NGL'),
  TeamSeed(id: 'team-6', name: 'Silverlake Kestrels', abbreviation: 'SLK'),
  TeamSeed(id: 'team-7', name: 'Verdant Union', abbreviation: 'VDU'),
  TeamSeed(id: 'team-8', name: 'Cinder Bay Embers', abbreviation: 'CBE'),
];

final class TeamSeed {
  const TeamSeed({
    required this.id,
    required this.name,
    required this.abbreviation,
  });

  final String id;
  final String name;
  final String abbreviation;
}
