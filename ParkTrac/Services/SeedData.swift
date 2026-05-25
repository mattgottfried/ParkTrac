import Foundation

// MARK: - Seed Restaurants

struct SeedRestaurant {
    let name: String
    let park: String
    let resort: String
    let category: String
}

let seedRestaurants: [SeedRestaurant] = [

    // MARK: Magic Kingdom
    SeedRestaurant(name: "Be Our Guest Restaurant", park: "Magic Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Cinderella's Royal Table", park: "Magic Kingdom", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "The Crystal Palace", park: "Magic Kingdom", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "Liberty Tree Tavern", park: "Magic Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Tony's Town Square Restaurant", park: "Magic Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Skipper Canteen", park: "Magic Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Columbia Harbour House", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Cosmic Ray's Starlight Café", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Pecos Bill Tall Tale Inn and Cafe", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Pinocchio Village Haus", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Casey's Corner", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Main Street Bakery", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "The Lunching Pad", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Aloha Isle", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Sleepy Hollow", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Tortuga Tavern", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "The Friar's Nook", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Cheshire Cafe", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Storybook Treats", park: "Magic Kingdom", resort: "Walt Disney World", category: "Quick Service"),

    // MARK: EPCOT
    SeedRestaurant(name: "Akershus Royal Banquet Hall", park: "EPCOT", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "Biergarten Restaurant", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Coral Reef Restaurant", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Garden Grill Restaurant", park: "EPCOT", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "La Hacienda de San Angel", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Le Cellier Steakhouse", park: "EPCOT", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Monsieur Paul", park: "EPCOT", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Nine Dragons Restaurant", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Rose & Crown Dining Room", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "San Angel Inn Restaurante", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Space 220", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Spice Road Table", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Takumi-Tei", park: "EPCOT", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Teppan Edo", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Tokyo Dining", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Tutto Italia Ristorante", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Via Napoli Ristorante e Pizzeria", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Chefs de France", park: "EPCOT", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Connections Café and Eatery", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Electric Umbrella", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Katsura Grill", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Kringla Bakeri og Kafe", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Les Halles Boulangerie-Patisserie", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Lotus Blossom Café", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Regal Eagle Smokehouse", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Sunshine Seasons", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Tangierine Café", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Yorkshire County Fish Shop", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Shiki-Sai: Sushi Izakaya", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "L'Artisan des Glaces", park: "EPCOT", resort: "Walt Disney World", category: "Quick Service"),

    // MARK: Hollywood Studios
    SeedRestaurant(name: "50's Prime Time Café", park: "Hollywood Studios", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Hollywood Brown Derby", park: "Hollywood Studios", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Mama Melrose's Ristorante Italiano", park: "Hollywood Studios", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Oga's Cantina", park: "Hollywood Studios", resort: "Walt Disney World", category: "Lounge"),
    SeedRestaurant(name: "Sci-Fi Dine-In Theater Restaurant", park: "Hollywood Studios", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "ABC Commissary", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Backlot Express", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Docking Bay 7 Food and Cargo", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Fairfax Fare", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Ronto Roasters", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Woody's Lunch Box", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "PizzeRizzo", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "The Trolley Car Café", park: "Hollywood Studios", resort: "Walt Disney World", category: "Quick Service"),

    // MARK: Animal Kingdom
    SeedRestaurant(name: "Tiffins Restaurant", park: "Animal Kingdom", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Yak & Yeti Restaurant", park: "Animal Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Rainforest Cafe at Animal Kingdom", park: "Animal Kingdom", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Tusker House Restaurant", park: "Animal Kingdom", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "Flame Tree Barbecue", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Harambe Market", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Pizzafari", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Restaurantosaurus", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Satu'li Canteen", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),
    SeedRestaurant(name: "Yak & Yeti Local Food Cafes", park: "Animal Kingdom", resort: "Walt Disney World", category: "Quick Service"),

    // MARK: Disney Springs
    SeedRestaurant(name: "Morimoto Asia", park: "Disney Springs", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "The BOATHOUSE", park: "Disney Springs", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "STK Orlando", park: "Disney Springs", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Paddlefish", park: "Disney Springs", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Maria & Enzo's Ristorante", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Enzo's Hideaway", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "T-REX", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Splitsville Luxury Lanes", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Chef Art Smith's Homecomin'", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Wine Bar George", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Wolfgang Puck Bar & Grill", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Jaleo by José Andrés", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Raglan Road Irish Pub", park: "Disney Springs", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Pizza Ponte", park: "Disney Springs", resort: "Walt Disney World", category: "Quick Service"),

    // MARK: Disney Resort Restaurants
    SeedRestaurant(name: "California Grill", park: "Contemporary Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Chef Mickey's", park: "Contemporary Resort", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "The Wave", park: "Contemporary Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Narcoossee's", park: "Grand Floridian Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Victoria & Albert's", park: "Grand Floridian Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Citricos", park: "Grand Floridian Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Grand Floridian Café", park: "Grand Floridian Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "1900 Park Fare", park: "Grand Floridian Resort", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "'Ohana", park: "Polynesian Village Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Kona Café", park: "Polynesian Village Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Spirit of Aloha Dinner Show", park: "Polynesian Village Resort", resort: "Walt Disney World", category: "Dinner Show"),
    SeedRestaurant(name: "Storybook Dining at Artist Point", park: "Wilderness Lodge", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "Whispering Canyon Cafe", park: "Wilderness Lodge", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Boma – Flavors of Africa", park: "Animal Kingdom Lodge", resort: "Walt Disney World", category: "Buffet"),
    SeedRestaurant(name: "Jiko – The Cooking Place", park: "Animal Kingdom Lodge", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Sanaa", park: "Animal Kingdom Lodge", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Topolino's Terrace", park: "Riviera Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Flying Fish", park: "BoardWalk Inn", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Trattoria al Forno", park: "BoardWalk Inn", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Ale & Compass", park: "Yacht Club Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Cape May Café", park: "Beach Club Resort", resort: "Walt Disney World", category: "Character Dining"),
    SeedRestaurant(name: "Hoop-Dee-Doo Musical Revue", park: "Fort Wilderness", resort: "Walt Disney World", category: "Dinner Show"),
    SeedRestaurant(name: "Trail's End Restaurant", park: "Fort Wilderness", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Olivia's Café", park: "Old Key West Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Turf Club Bar and Grill", park: "Saratoga Springs Resort", resort: "Walt Disney World", category: "Table Service"),
    SeedRestaurant(name: "Toledo – Tapas, Steak & Seafood", park: "Coronado Springs Resort", resort: "Walt Disney World", category: "Signature Dining"),
    SeedRestaurant(name: "Rix Sports Bar & Grill", park: "Coronado Springs Resort", resort: "Walt Disney World", category: "Table Service"),

    // MARK: Universal Studios Florida
    SeedRestaurant(name: "The Leaky Cauldron", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Finnegan's Bar & Grill", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Lombard's Seafood Grille", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Mel's Drive-In", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Richter's Burger Co", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Louie's Italian Restaurant", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Krusty Burger", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Bumblebee Man's Taco Truck", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Lard Lad Donuts", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Duff Brewery", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Beverly Hills Boulangerie", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "San Francisco Pastry Company", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Café La Bamba", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "The Hopping Pot", park: "Universal Studios Florida", resort: "Universal Orlando", category: "Quick Service"),

    // MARK: Islands of Adventure
    SeedRestaurant(name: "Three Broomsticks", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Hog's Head Pub", park: "Islands of Adventure", resort: "Universal Orlando", category: "Lounge"),
    SeedRestaurant(name: "Mythos Restaurant", park: "Islands of Adventure", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Confisco Grille", park: "Islands of Adventure", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Circus McGurkus Café Stoo-pendous", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Thunder Falls Terrace", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Comic Strip Café", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Captain America Diner", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Green Eggs and Ham Café", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Croissant Moon Bakery", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "The Burger Digs", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Blondie's", park: "Islands of Adventure", resort: "Universal Orlando", category: "Quick Service"),

    // MARK: Epic Universe
    SeedRestaurant(name: "The Wizarding World Tavern", park: "Epic Universe", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Helios Grand Buffet", park: "Epic Universe", resort: "Universal Orlando", category: "Buffet"),
    SeedRestaurant(name: "Minion Café", park: "Epic Universe", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Monster Mash Kitchen", park: "Epic Universe", resort: "Universal Orlando", category: "Quick Service"),

    // MARK: Universal CityWalk
    SeedRestaurant(name: "Emeril's Tchoup Chop", park: "CityWalk", resort: "Universal Orlando", category: "Signature Dining"),
    SeedRestaurant(name: "Margaritaville", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "NBC Sports Grill & Brew", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Antojitos Authentic Mexican Food", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Vivo Italian Kitchen", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "The Cowfish Sushi Burger Bar", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Hard Rock Cafe Orlando", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Pat O'Brien's Orlando", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Bob Marley – A Tribute to Freedom", park: "CityWalk", resort: "Universal Orlando", category: "Table Service"),
    SeedRestaurant(name: "Red Oven Pizza Bakery", park: "CityWalk", resort: "Universal Orlando", category: "Quick Service"),
    SeedRestaurant(name: "Bread Box Handcrafted Sandwiches", park: "CityWalk", resort: "Universal Orlando", category: "Quick Service"),
]

// MARK: - Seed Hotels

struct SeedHotel {
    let name: String
    let resort: String
    let tier: String
}

let seedHotels: [SeedHotel] = [
    // MARK: Walt Disney World – Deluxe
    SeedHotel(name: "Disney's Grand Floridian Resort & Spa", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Contemporary Resort", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Polynesian Village Resort", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Wilderness Lodge", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Animal Kingdom Lodge", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's BoardWalk Inn", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Beach Club Resort", resort: "Walt Disney World", tier: "Deluxe"),
    SeedHotel(name: "Disney's Yacht Club Resort", resort: "Walt Disney World", tier: "Deluxe"),

    // MARK: Walt Disney World – DVC
    SeedHotel(name: "Disney's Old Key West Resort", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's Saratoga Springs Resort & Spa", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's Riviera Resort", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's Polynesian Villas & Bungalows", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's Animal Kingdom Villas – Kidani Village", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's Bay Lake Tower", resort: "Walt Disney World", tier: "Disney Vacation Club"),
    SeedHotel(name: "Disney's BoardWalk Villas", resort: "Walt Disney World", tier: "Disney Vacation Club"),

    // MARK: Walt Disney World – Moderate
    SeedHotel(name: "Disney's Coronado Springs Resort", resort: "Walt Disney World", tier: "Moderate"),
    SeedHotel(name: "Disney's Caribbean Beach Resort", resort: "Walt Disney World", tier: "Moderate"),
    SeedHotel(name: "Disney's Port Orleans Resort – French Quarter", resort: "Walt Disney World", tier: "Moderate"),
    SeedHotel(name: "Disney's Port Orleans Resort – Riverside", resort: "Walt Disney World", tier: "Moderate"),

    // MARK: Walt Disney World – Value
    SeedHotel(name: "Disney's All-Star Movies Resort", resort: "Walt Disney World", tier: "Value"),
    SeedHotel(name: "Disney's All-Star Music Resort", resort: "Walt Disney World", tier: "Value"),
    SeedHotel(name: "Disney's All-Star Sports Resort", resort: "Walt Disney World", tier: "Value"),
    SeedHotel(name: "Disney's Art of Animation Resort", resort: "Walt Disney World", tier: "Value"),
    SeedHotel(name: "Disney's Pop Century Resort", resort: "Walt Disney World", tier: "Value"),

    // MARK: Walt Disney World – Other
    SeedHotel(name: "Disney's Fort Wilderness Resort & Campground", resort: "Walt Disney World", tier: "Campground"),
    SeedHotel(name: "Disney's Shades of Green Resort", resort: "Walt Disney World", tier: "Military"),
    SeedHotel(name: "Walt Disney World Swan", resort: "Walt Disney World", tier: "Partner Hotel"),
    SeedHotel(name: "Walt Disney World Dolphin", resort: "Walt Disney World", tier: "Partner Hotel"),
    SeedHotel(name: "Walt Disney World Swan Reserve", resort: "Walt Disney World", tier: "Partner Hotel"),
    SeedHotel(name: "Four Seasons Orlando at Walt Disney World Resort", resort: "Walt Disney World", tier: "Partner Hotel"),

    // MARK: Universal Orlando – Premier
    SeedHotel(name: "Loews Portofino Bay Hotel", resort: "Universal Orlando", tier: "Premier"),
    SeedHotel(name: "Hard Rock Hotel Orlando", resort: "Universal Orlando", tier: "Premier"),
    SeedHotel(name: "Loews Royal Pacific Resort", resort: "Universal Orlando", tier: "Premier"),

    // MARK: Universal Orlando – Preferred
    SeedHotel(name: "Loews Sapphire Falls Resort", resort: "Universal Orlando", tier: "Preferred"),

    // MARK: Universal Orlando – Standard & Value
    SeedHotel(name: "Universal's Cabana Bay Beach Resort", resort: "Universal Orlando", tier: "Standard"),
    SeedHotel(name: "Universal's Aventura Hotel", resort: "Universal Orlando", tier: "Standard"),
    SeedHotel(name: "Universal's Endless Summer Resort – Surfside Inn and Suites", resort: "Universal Orlando", tier: "Value"),
    SeedHotel(name: "Universal's Endless Summer Resort – Dockside Inn and Suites", resort: "Universal Orlando", tier: "Value"),

    // MARK: Universal Orlando – Epic Universe Hotels (new)
    SeedHotel(name: "Universal's Terra Luna Resort", resort: "Universal Orlando", tier: "Standard"),
    SeedHotel(name: "Universal's Stella Nova Resort", resort: "Universal Orlando", tier: "Standard"),
    SeedHotel(name: "Universal's Galaxy Hotel", resort: "Universal Orlando", tier: "Standard"),
    SeedHotel(name: "Universal Epic Hotel", resort: "Universal Orlando", tier: "Premier"),
]
