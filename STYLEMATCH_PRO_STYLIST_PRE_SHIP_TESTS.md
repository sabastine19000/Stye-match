# StyleMatch Pro Stylist Pre-Ship Test Cases

These tests verify the required data flow:

`image -> detectGarmentAttributes -> shouldRequestRetake/validateFashionImage -> calculateStyleScore -> explainScore -> getShoppingRecommendations -> saveOutfitScan`

## Test 1: Blurry Or Unclear Photo

**Purpose:** The app should request a clearer image before scoring.

**Setup:**
- Use a deliberately blurry outfit photo or a photo with very low contrast.
- Keep ChatGPT/AI enabled if available.

**Steps:**
1. Open StyleMatch Pro.
2. Go to Scan.
3. Upload or capture the blurry image.
4. Tap Generate Style Score.

**Expected Result:**
- `validateFashionImage` returns `.poorQuality`.
- No style score is generated.
- No ChatGPT explanation request is sent.
- User sees a helpful retake message such as `Please retake the photo` or `We need a clearer outfit image for accurate scoring`.

**Fail If:**
- The app shows a confident score.
- The app sends the image to AI for an explanation.
- The app labels the outfit despite poor quality.

## Test 2: No Person Or Clothing In Frame

**Purpose:** Non-clothing images must not be scored.

**Setup:**
- Use an image of a wall, empty room, food, car, or furniture with no visible clothing.

**Steps:**
1. Open Scan.
2. Upload the non-clothing image.
3. Tap Generate Style Score.

**Expected Result:**
- `validateFashionImage` returns `.rejected` or `.unknown`.
- No score is generated.
- No ChatGPT explanation request is sent.
- User sees `No outfit detected` or a clearer outfit-photo message.

**Fail If:**
- The app scores the wall/object.
- The app classifies it as casual, business casual, traditional wear, or any outfit category.

## Test 3: Empty Inventory

**Purpose:** Shopping AI must handle no sale items safely.

**Setup:**
- Temporarily make `activeSaleItems` return an empty array, or configure the product catalog so no products have `salePrice < originalPrice`.

**Steps:**
1. Open Smart Shopping.
2. Tap Refresh AI Sale Matches.

**Expected Result:**
- The app does not call the AI shopping prompt.
- User sees `No sale items available right now.`
- No crash occurs.

**Fail If:**
- The app sends an empty sale list to AI.
- The app invents sale products.
- The app crashes or displays blank UI.

## Test 4: API Timeout Or Non-200 Response

**Purpose:** AI failures must fall back gracefully.

**Setup:**
- Disable network, use an invalid key, or force the AI endpoint to time out.

**Steps:**
1. Scan a valid outfit.
2. Wait for ChatGPT score explanation.
3. Open AI Assist and ask a question.
4. Open Smart Shopping and tap Refresh AI Sale Matches.

**Expected Result:**
- Scan score still appears because scoring is local/deterministic.
- Chat explanation failure shows a user-friendly message.
- AI Assist shows `AI Assist is having trouble connecting right now. Please try again.`
- Smart Shopping falls back to local validated sale recommendations.

**Fail If:**
- The score fails only because AI is unavailable.
- The app crashes.
- Raw API error bodies are shown to customers.

## Test 5: First-Time User With No Scan History

**Purpose:** Empty history must not break AI shopping or AI Assist.

**Setup:**
- Clear saved data or install fresh.
- Do not scan any previous outfit.

**Steps:**
1. Open Smart Shopping.
2. Tap Refresh AI Sale Matches.
3. Scan one valid outfit.
4. Open AI Assist for that scan.

**Expected Result:**
- `recentOutfitHistory` returns an empty array without crashing.
- Shopping recommendations use current profile/catalog context.
- The first scan saves to local history.
- AI Assist uses the current scan as context.

**Fail If:**
- The app assumes history exists.
- Shopping AI crashes or sends malformed history.
- AI Assist asks the user to manually repeat score/clothing details already visible on screen.

