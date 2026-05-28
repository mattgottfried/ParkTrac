import Foundation

struct CharacterAppearance: Identifiable {
    let id = UUID()
    let character: String
    let park: String
    let resort: String
    let location: String
    let typicalTimes: String
    let notes: String
}

let allCharacterAppearances: [CharacterAppearance] = [
    // Magic Kingdom
    CharacterAppearance(character: "Mickey Mouse", park: "Magic Kingdom", resort: "Walt Disney World", location: "Town Square Theater", typicalTimes: "Park open–7pm", notes: "Lightning Lane required"),
    CharacterAppearance(character: "Minnie Mouse", park: "Magic Kingdom", resort: "Walt Disney World", location: "Town Square Theater", typicalTimes: "Park open–7pm", notes: "Lightning Lane required"),
    CharacterAppearance(character: "Cinderella & Elena", park: "Magic Kingdom", resort: "Walt Disney World", location: "Princess Fairytale Hall", typicalTimes: "Park open–7pm", notes: "Lightning Lane required"),
    CharacterAppearance(character: "Tiana & Rapunzel", park: "Magic Kingdom", resort: "Walt Disney World", location: "Princess Fairytale Hall", typicalTimes: "Park open–7pm", notes: "Lightning Lane required"),
    CharacterAppearance(character: "Buzz Lightyear", park: "Magic Kingdom", resort: "Walt Disney World", location: "Tomorrowland, near Buzz ride", typicalTimes: "Varies", notes: "Check daily schedule"),
    CharacterAppearance(character: "Tinker Bell", park: "Magic Kingdom", resort: "Walt Disney World", location: "Town Square / Various", typicalTimes: "Morning", notes: "Seasonal / check app"),

    // EPCOT
    CharacterAppearance(character: "Elsa & Anna", park: "EPCOT", resort: "Walt Disney World", location: "Royal Sommerhus (Norway)", typicalTimes: "10am–6pm", notes: "Lightning Lane available"),
    CharacterAppearance(character: "Remy", park: "EPCOT", resort: "Walt Disney World", location: "France Pavilion", typicalTimes: "11am–4pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Belle", park: "EPCOT", resort: "Walt Disney World", location: "France Pavilion", typicalTimes: "11am–4pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Snow White", park: "EPCOT", resort: "Walt Disney World", location: "Germany Pavilion", typicalTimes: "Varies", notes: "Seasonal"),

    // Hollywood Studios
    CharacterAppearance(character: "Woody & Jessie", park: "Hollywood Studios", resort: "Walt Disney World", location: "Toy Story Land", typicalTimes: "10am–5pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Rey", park: "Hollywood Studios", resort: "Walt Disney World", location: "Galaxy's Edge", typicalTimes: "Varies", notes: "Roaming character"),
    CharacterAppearance(character: "Chewbacca", park: "Hollywood Studios", resort: "Walt Disney World", location: "Galaxy's Edge", typicalTimes: "Varies", notes: "Roaming character"),

    // Animal Kingdom
    CharacterAppearance(character: "Donald (Safari)", park: "Animal Kingdom", resort: "Walt Disney World", location: "Adventurers Outpost", typicalTimes: "9am–5pm", notes: "With Daisy; Lightning Lane"),
    CharacterAppearance(character: "Daisy (Safari)", park: "Animal Kingdom", resort: "Walt Disney World", location: "Adventurers Outpost", typicalTimes: "9am–5pm", notes: "With Donald; Lightning Lane"),
    CharacterAppearance(character: "Russell & Dug", park: "Animal Kingdom", resort: "Walt Disney World", location: "Discovery Island", typicalTimes: "Varies", notes: "Check daily schedule"),

    // Universal Studios Florida
    CharacterAppearance(character: "SpongeBob SquarePants", park: "Universal Studios Florida", resort: "Universal Orlando", location: "SpongeBob StorePants area", typicalTimes: "10am–4pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Gru & Minions", park: "Universal Studios Florida", resort: "Universal Orlando", location: "Despicable Me area", typicalTimes: "10am–5pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Shrek & Donkey", park: "Universal Studios Florida", resort: "Universal Orlando", location: "Shrek 4D area", typicalTimes: "Varies", notes: "Check daily schedule"),

    // Islands of Adventure
    CharacterAppearance(character: "Spider-Man", park: "Islands of Adventure", resort: "Universal Orlando", location: "Marvel Super Hero Island", typicalTimes: "11am–5pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "Captain America", park: "Islands of Adventure", resort: "Universal Orlando", location: "Marvel Super Hero Island", typicalTimes: "11am–5pm", notes: "Check daily schedule"),
    CharacterAppearance(character: "The Cat in the Hat", park: "Islands of Adventure", resort: "Universal Orlando", location: "Seuss Landing", typicalTimes: "10am–4pm", notes: "Check daily schedule"),
]
