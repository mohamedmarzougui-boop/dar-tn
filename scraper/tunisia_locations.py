# Tunisia's 24 governorates, each mapped to its delegations. Mirrors
# mobile_app/lib/tunisia_locations.dart - duplicated rather than shared
# across runtimes since this is static reference data (Tunisia's
# administrative divisions don't change), not worth a shared-data build step.
TUNISIA_LOCATIONS = {
    "Tunis": [
        "Bab Bhar", "Bab Souika", "Carthage", "Cité El Khadra", "Djebel Jelloud",
        "El Kabaria", "El Kram", "El Menzah", "El Omrane", "El Omrane Supérieur",
        "El Ouardia", "Essijoumi", "Ettahrir", "Ezzouhour", "Hraïria",
        "La Goulette", "La Marsa", "Le Bardo", "Médina", "Sidi El Béchir", "Sidi Hassine",
        # Well-known modern neighborhoods, not official delegation names in
        # their own right (they fall under El Kram administratively) but
        # commonly used by name for real estate.
        "Les Berges du Lac", "Lac 2",
    ],
    "Ariana": ["Ariana Ville", "Ettadhamen", "Kalaat Al-Andalous", "La Soukra", "Mnihla", "Raoued", "Sidi Thabet"],
    "Ben Arous": [
        "Ben Arous", "Bou Mhel el-Bassatine", "El Mourouj", "Ezzahra", "Fouchana",
        "Hammam Chott", "Hammam Lif", "Medina Jedida", "Mégrine", "Mohamedia",
        "Mornag", "Nouvelle Medina", "Radès",
    ],
    "Manouba": ["Manouba", "Den Den", "Douar Hicher", "Oued Ellil", "Mornaguia", "Borj El Amri", "El Battan", "Jedaida", "Tebourba"],
    "Nabeul": [
        "Nabeul", "Dar Chaabane El Fehri", "Beni Khiar", "El Mida", "Korba",
        "Menzel Temime", "Kelibia", "Haouaria", "Takelsa", "Soliman",
        "Grombalia", "Bou Argoub", "Hammamet", "Beni Khalled", "Menzel Bouzelfa", "Zaouiet Djedidi",
    ],
    "Zaghouan": ["Zaghouan", "Bir Mcherga", "El Fahs", "Nadhour", "Saouaf", "Zriba"],
    "Bizerte": [
        "Bizerte Nord", "Bizerte Sud", "Djoumine", "El Alia", "Ghar El Melh",
        "Ghezala", "Mateur", "Menzel Bourguiba", "Menzel Jemil", "Ras Jebel",
        "Sejnane", "Tinja", "Utique", "Zarzouna",
    ],
    "Béja": ["Béja Nord", "Béja Sud", "Amdoun", "Goubellat", "Mejez El Bab", "Nefza", "Teboursouk", "Testour", "Thibar"],
    "Jendouba": ["Jendouba", "Jendouba Nord", "Ain Draham", "Balta-Bou Aouene", "Bou Salem", "Fernana", "Ghardimaou", "Oued Meliz", "Tabarka"],
    "Le Kef": [
        "Kef Est", "Kef Ouest", "Dahmani", "Jerissa", "Kalaat Khasba", "Kalaat Senan",
        "Ksour", "Nebeur", "Sakiet Sidi Youssef", "Tajerouine", "Touiref",
    ],
    "Siliana": ["Siliana Nord", "Siliana Sud", "Bargou", "Bou Arada", "El Aroussa", "Gaafour", "Kesra", "Makthar", "Rouhia", "Sidi Bou Rouis"],
    "Kairouan": ["Kairouan Nord", "Kairouan Sud", "Bou Hajla", "Chebika", "Echrarda", "Hajeb El Ayoun", "Haffouz", "Nasrallah", "Oueslatia", "Sbikha"],
    "Kasserine": [
        "Kasserine Nord", "Kasserine Sud", "El Ayoun", "Ezzouhour", "Fériana",
        "Foussana", "Hassi El Ferid", "Hidra", "Jedelienne", "Majel Bel Abbes", "Sbeitla", "Sbiba", "Thala",
    ],
    "Sidi Bouzid": [
        "Sidi Bouzid Est", "Sidi Bouzid Ouest", "Bir El Hafey", "Cebbala Ouled Asker",
        "Jilma", "Menzel Bouzaiane", "Meknassy", "Mezzouna", "Ouled Haffouz", "Regueb", "Sidi Ali Ben Aoun", "Souk Jedid",
    ],
    "Sousse": [
        "Sousse Médina", "Sousse Riadh", "Sousse Jawhara", "Sousse Ville", "Akouda",
        "Bouficha", "Enfida", "Hammam Sousse", "Hergla", "Kalaa Kebira",
        "Kalaa Seghira", "Kondar", "Msaken", "Sidi Bou Ali", "Sidi El Heni", "Zaouiet Sousse",
    ],
    "Monastir": [
        "Monastir", "Bekalta", "Bembla", "Beni Hassen", "Jemmal", "Ksar Hellal",
        "Ksibet El Mediouni", "Moknine", "Ouerdanine", "Sahline", "Sayada-Lamta-Bou Hajar", "Teboulba", "Zeramdine",
    ],
    "Mahdia": ["Mahdia", "Bou Merdes", "Chebba", "Chorbane", "El Jem", "Hebira", "Ksour Essef", "Melloulèche", "Ouled Chamekh", "Sidi Alouane"],
    "Sfax": [
        "Sfax Ville", "Sfax Ouest", "Sfax Sud", "Sakiet Eddaier", "Sakiet Ezzit",
        "Agareb", "Bir Ali Ben Khalifa", "El Amra", "El Hencha", "Ghraiba",
        "Jebeniana", "Kerkennah", "Mahres", "Menzel Chaker", "Skhira", "Thyna",
    ],
    "Gabès": ["Gabès Médina", "Gabès Ouest", "Gabès Sud", "El Hamma", "El Metouia", "Ghannouch", "Mareth", "Matmata", "Menzel Habib", "Nouvelle Matmata", "Oudhref"],
    "Médenine": ["Médenine Nord", "Médenine Sud", "Ben Gardane", "Beni Khedache", "Djerba Ajim", "Djerba Houmt Souk", "Djerba Midoun", "Sidi Makhlouf", "Zarzis"],
    "Tataouine": ["Tataouine Nord", "Tataouine Sud", "Bir Lahmar", "Dhehiba", "Ghomrassen", "Remada", "Smar"],
    "Gafsa": ["Gafsa Nord", "Gafsa Sud", "Belkhir", "El Guettar", "El Ksar", "Mdhilla", "Métlaoui", "Moularès", "Redeyef", "Sened", "Sidi Aïch"],
    "Tozeur": ["Tozeur", "Degache", "Hazoua", "Nefta", "Tameghza"],
    "Kébili": ["Kébili Nord", "Kébili Sud", "Douz Nord", "Douz Sud", "Faouar", "Souk Lahad"],
}
