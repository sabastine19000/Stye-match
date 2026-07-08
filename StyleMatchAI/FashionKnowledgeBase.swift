import Foundation

enum FashionKnowledgeBase {
    static let summary = """
    StyleMatch Pro fashion knowledge database:
    Color theory: evaluate contrast, harmony, temperature, neutrals, accent colors, saturation, and whether shoes or accessories bridge the palette.
    Formality: separate style category from occasion. Casual, smart casual, business casual, formal, ceremonial, streetwear, athletic, traditional wear, cultural formal wear, and religious attire can overlap with different events.
    Occasion matching: score against work, church, wedding, traditional wedding, interview, date night, travel, gym, graduation, cultural festival, ceremony, and evening events.
    Weather matching: consider temperature, rain, humidity, wind, sun, layers, breathable fabrics, closed shoes, jackets, and after-sunset comfort.
    Shoes: match color, polish, occasion, weather, and contrast. Do not recommend the same shoe every time.
    Accessories: use watches, belts, bags, hats, jewelry, scarves, and layers to complete an outfit only when they improve the look.
    Fabric and season: linen and cotton fit heat; wool, denim, leather, and heavier knits fit cooler weather; shiny or embroidered fabrics can be formal or ceremonial.
    Traditional and cultural attire: recognize and respect Agbada, Senator Wear, Isiagu, Buba and Iro, Ankara, Aso Oke, Dashiki, Kaftan, Kente, Kanzu, Gomesi, Shuka, Habesha Kemis, Boubou, Grand Boubou, Djellaba, Kimono, Yukata, Hanfu, Qipao, Cheongsam, Hanbok, Saree, Salwar Kameez, Kurta Pajama, Sherwani, Lehenga, Shalwar Kameez, Ao Dai, Chut Thai, Batik, Thobe, Kandura, Dishdasha, Bisht, Abaya, Jalabiya, Keffiyeh, Shemagh, Kilt, Lederhosen, Dirndl, Vyshyvanka, Flamenco Dress, Charro Suit, Huipil, Pollera, Poncho, Andean clothing, Lava-lava, Pareo, Maori traditional garments, Samoan ceremonial clothing, and Tongan ceremonial clothing.
    Cultural guardrail: identify clothing only. Never infer race, ethnicity, nationality, religion, age, gender, body judgment, or identity. Do not call traditional clothing casual by default.
    Score explanation: StyleMatch AI owns the score. ChatGPT explains and improves it using the facts, confidence levels, user profile, weather, and fashion rules.
    Accuracy guardrails: use "appears to be" when confidence is low. Do not guess brands unless the app provides high confidence. If the image is poor or non-clothing, ask for a better photo instead of styling it.
    """
}
