import Foundation

/// A group's icon, picked from its name (Sabit, 2026-11-12): "Car" shows 🚗, "কক্সবাজার ট্যুর"
/// shows 🏖️. It isn't chosen by hand and isn't stored: every phone works it out from the
/// name, so a shared group shows the same icon everywhere and a rename updates it. Nil means
/// nothing matched and the app shows the TakaDe mark instead.
///
/// The word list lives here, on the phone: no lookup service, no downloaded images.
public enum GroupIcon {
    public static func emoji(for name: String) -> String? {
        // An emoji typed into the name wins: "🏸 Thursday" is a badminton group.
        if let typed = firstEmoji(in: name) { return typed }
        let words = name.lowercased().precomposedStringWithCanonicalMapping
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let phrase = " " + words.joined(separator: " ") + " "
        for (emoji, keys) in table where keys.contains(where: { matches($0, words: words, phrase: phrase) }) {
            return emoji
        }
        return nil
    }

    // MARK: - Matching

    private static let separators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
        .union(.controlCharacters)

    /// Endings a word can carry and still be the same word: "cars", "trips", "Rafi's";
    /// in Bengali the case and article endings, so "গাড়ির" and "বিয়েতে" match but "বাসা"
    /// (home) doesn't match "বাস" (bus).
    private static let latinEndings = ["", "s", "es"]
    private static let bengaliEndings = ["", "র", "ের", "এর", "ে", "য়", "তে", "এ", "টা", "টি", "গুলো", "দের", "য়ে"]

    private static func matches(_ key: String, words: [String], phrase: String) -> Bool {
        let key = key.precomposedStringWithCanonicalMapping
        if key.contains(" ") { return phrase.contains(" \(key) ") }
        let endings = key.unicodeScalars.allSatisfy(\.isASCII) ? latinEndings : bengaliEndings
        // Compared by code point, not by letter: a Bengali vowel sign joins the letter
        // before it, so "ঈদের" doesn't start with the letters of "ঈদ", only its code points.
        let keyScalars = Array(key.unicodeScalars)
        return words.contains { word in
            let scalars = Array(word.unicodeScalars)
            guard scalars.count >= keyScalars.count, Array(scalars[..<keyScalars.count]) == keyScalars else { return false }
            var rest = String.UnicodeScalarView()
            rest.append(contentsOf: scalars[keyScalars.count...])
            return endings.contains(String(rest).precomposedStringWithCanonicalMapping)
        }
    }

    private static func firstEmoji(in name: String) -> String? {
        name.first { character in
            guard let scalar = character.unicodeScalars.first else { return false }
            // Digits, # and * are "emoji" too; only take real pictographs.
            return scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C && character.unicodeScalars.count > 1)
        }.map(String.init)
    }

    // MARK: - Words
    //
    // Checked top to bottom, so occasions and places come before the general "trip" or
    // "food": "Cox's Bazar trip" is a beach, "Office iftar" is an iftar. English, the
    // way people write Bangla in English letters, then Bengali.

    static let table: [(String, [String])] = [
        // Occasions
        ("💍", ["wedding", "biye", "biya", "holud", "gaye holud", "reception", "engagement", "বিয়ে", "বিয়া", "হলুদ", "গায়ে হলুদ", "বৌভাত"]),
        ("🎂", ["birthday", "bday", "cake", "জন্মদিন", "বার্থডে"]),
        ("🌙", ["iftar", "ramadan", "ramzan", "romjan", "sehri", "ইফতার", "রমজান", "সেহরি"]),
        ("🐄", ["qurbani", "kurbani", "korbani", "cow", "কুরবানি", "কোরবানি", "গরু"]),
        ("🕌", ["eid", "ঈদ", "মসজিদ", "mosque"]),
        ("🪔", ["puja", "pujo", "durga puja", "diwali", "পূজা", "পুজো", "দিওয়ালি"]),
        ("🎄", ["christmas", "xmas", "বড়দিন"]),
        ("🌸", ["boishakh", "baishakh", "pohela boishakh", "noboborsho", "বৈশাখ", "নববর্ষ"]),
        ("🎓", ["graduation", "convocation", "university", "uni", "varsity", "campus", "college", "batch", "classmates", "ভার্সিটি", "বিশ্ববিদ্যালয়", "কলেজ", "ক্যাম্পাস", "ব্যাচ"]),
        ("🎉", ["party", "celebration", "reunion", "farewell", "পার্টি", "রিইউনিয়ন"]),
        ("🧺", ["picnic", "পিকনিক", "বনভোজন"]),

        // Places
        ("🏖️", ["beach", "sea", "cox", "coxs bazar", "coxsbazar", "kuakata", "saint martin", "st martin", "সমুদ্র", "সৈকত", "কক্সবাজার", "কুয়াকাটা", "সেন্টমার্টিন"]),
        ("⛰️", ["mountain", "hill", "hills", "hike", "hiking", "trek", "trekking", "bandarban", "sajek", "pahar", "পাহাড়", "বান্দরবান", "সাজেক"]),
        ("🏕️", ["camp", "camping", "ক্যাম্প", "ক্যাম্পিং"]),
        ("🍃", ["sylhet", "srimangal", "tea garden", "সিলেট", "শ্রীমঙ্গল"]),
        ("🏨", ["hotel", "resort", "হোটেল", "রিসোর্ট"]),

        // Getting around
        ("🚗", ["car", "carpool", "gari", "gaari", "drive", "গাড়ি"]),
        ("🏍️", ["bike", "motorbike", "motorcycle", "বাইক", "মোটরসাইকেল"]),
        ("🚲", ["cycle", "bicycle", "cycling", "সাইকেল"]),
        ("🛺", ["cng", "rickshaw", "riksha", "auto", "রিকশা", "সিএনজি"]),
        ("🚕", ["uber", "pathao", "taxi", "ride", "rides", "উবার", "পাঠাও"]),
        ("🚌", ["bus", "বাস"]),
        ("🚆", ["train", "rail", "metro", "ট্রেন", "রেল", "মেট্রো"]),
        ("🚢", ["launch", "ship", "cruise", "steamer", "লঞ্চ", "জাহাজ"]),
        ("⛵", ["boat", "nouka", "নৌকা"]),
        ("✈️", ["flight", "flights", "plane", "airport", "fly", "ফ্লাইট", "বিমান"]),
        ("⛽", ["fuel", "petrol", "octane", "diesel", "তেল", "পেট্রোল"]),
        ("🧳", ["trip", "tour", "travel", "vacation", "holiday", "journey", "getaway", "ট্যুর", "ট্রিপ", "ভ্রমণ", "ছুটি"]),

        // Food
        ("🍛", ["biryani", "kacchi", "khichuri", "বিরিয়ানি", "কাচ্চি", "খিচুড়ি"]),
        ("🍕", ["pizza", "পিৎজা", "পিজ্জা"]),
        ("🍔", ["burger", "বার্গার"]),
        ("🍗", ["bbq", "barbecue", "grill", "বারবিকিউ"]),
        ("☕", ["coffee", "cafe", "কফি", "ক্যাফে"]),
        ("🍵", ["tea", "cha", "চা"]),
        ("🍽️", ["dinner", "lunch", "breakfast", "brunch", "food", "foodies", "restaurant", "khawa", "khawdawa", "dawat", "ডিনার", "লাঞ্চ", "খাবার", "খাওয়া", "দাওয়াত", "রেস্টুরেন্ট"]),
        ("🛒", ["bazar", "bazaar", "grocery", "groceries", "বাজার", "মুদি"]),

        // Home and work
        ("🍚", ["mess", "মেস"]),
        ("🔑", ["rent", "ভাড়া"]),
        ("🏠", ["home", "house", "flat", "flatmates", "roommates", "apartment", "basha", "bari", "বাসা", "বাড়ি", "ফ্ল্যাট"]),
        ("💡", ["electricity", "utilities", "utility", "bills", "bill", "current", "বিদ্যুৎ", "বিল"]),
        ("📶", ["wifi", "internet", "broadband", "ইন্টারনেট", "ওয়াইফাই"]),
        ("💼", ["office", "work", "colleagues", "team", "job", "অফিস", "কলিগ"]),
        ("🏫", ["school", "class", "coaching", "tuition", "স্কুল", "ক্লাস", "কোচিং"]),
        ("📚", ["books", "book", "study", "library", "বই", "পড়াশোনা"]),

        // Fun and sport
        ("⚽", ["football", "futsal", "soccer", "ফুটবল"]),
        ("🏏", ["cricket", "ক্রিকেট"]),
        ("🏸", ["badminton", "ব্যাডমিন্টন"]),
        ("🏋️", ["gym", "fitness", "workout", "জিম"]),
        ("🎮", ["game", "gaming", "playstation", "ps5", "গেম"]),
        ("🎬", ["movie", "movies", "cinema", "film", "netflix", "সিনেমা", "মুভি"]),
        ("🎵", ["concert", "music", "band", "gaan", "গান", "কনসার্ট"]),
        ("🛍️", ["shopping", "mall", "daraz", "কেনাকাটা", "শপিং"]),
        ("🎁", ["gift", "gifts", "present", "উপহার", "গিফট"]),

        // People and care
        ("👨‍👩‍👧", ["family", "poribar", "ফ্যামিলি", "পরিবার"]),
        ("👫", ["friends", "bondhu", "bondhura", "squad", "gang", "বন্ধু", "বন্ধুরা"]),
        ("❤️", ["couple", "love", "us two", "ভালোবাসা"]),
        ("🏥", ["hospital", "doctor", "medicine", "medical", "pharmacy", "হাসপাতাল", "ডাক্তার", "ওষুধ"]),
        ("🐾", ["pet", "pets", "dog", "cat", "বিড়াল", "কুকুর"]),
    ]
}
