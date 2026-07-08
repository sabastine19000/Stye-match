# StyleMatch Pro Shopping Release Checklist

StyleMatch Pro is an affiliate shopping marketplace only. It does not process payments, hold inventory, ship orders, manage returns, or provide retailer customer service.

## Retailer Readiness

| Retailer | Affiliate program/network to apply to | Adapter | Required config/env values | Proxy required | Current searchStatus |
|---|---|---|---|---|---|
| Nike | CJ or Nike-approved affiliate feed | `cj` | `CJ_PUBLISHER_ID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Macy's | CJ product feed | `cj` | `CJ_PUBLISHER_ID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Best Buy | Best Buy public Products API / affiliate approval | `bestbuy` | `BESTBUY_API_KEY`, retailer tracking ID in `RetailerConfig.json` | No for public Products API; affiliate tracking still configured locally | `pending` |
| Amazon | Amazon Associates + Product Advertising API | `amazon` | `PROXY_BASE_URL`, `AMAZON_PARTNER_TAG` | Yes | `pending` |
| Nordstrom | Rakuten Advertising | `rakuten` | `RAKUTEN_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Levi's | CJ or approved Levi's affiliate network | `cj` | `CJ_PUBLISHER_ID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Target | Impact.com | `impact` | `IMPACT_ACCOUNT_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Walmart | Impact.com or Walmart-approved affiliate feed | `impact` | `IMPACT_ACCOUNT_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Adidas | Rakuten Advertising or approved Adidas feed | `rakuten` | `RAKUTEN_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| H&M | Sovrn Commerce or approved affiliate feed | `sovrn` | `PROXY_BASE_URL`; Sovrn secret proxy-side only | Yes | `pending` |
| Zara | Sovrn Commerce or approved affiliate feed | `sovrn` | `PROXY_BASE_URL`; Sovrn secret proxy-side only | Yes | `pending` |
| SHEIN | Sovrn Commerce or approved affiliate feed | `sovrn` | `PROXY_BASE_URL`; Sovrn secret proxy-side only | Yes | `pending` |
| Fashion Nova | Sovrn Commerce or approved affiliate feed | `sovrn` | `PROXY_BASE_URL`; Sovrn secret proxy-side only | Yes | `pending` |
| Foot Locker | CJ or approved Foot Locker affiliate feed | `cj` | `CJ_PUBLISHER_ID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| DICK'S Sporting Goods | Impact.com or approved affiliate feed | `impact` | `IMPACT_ACCOUNT_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Sephora | Rakuten Advertising or approved affiliate feed | `rakuten` | `RAKUTEN_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |
| Ulta | Impact.com or approved affiliate feed | `impact` | `IMPACT_ACCOUNT_SID`, retailer tracking ID in `RetailerConfig.json` | Yes | `pending` |

## Required Local Config

Create `Secrets.xcconfig` locally from `Secrets.xcconfig.template`. Do not commit `Secrets.xcconfig`.

Required values:

- `BESTBUY_API_KEY`
- `PROXY_BASE_URL`
- `AMAZON_PARTNER_TAG`
- `IMPACT_ACCOUNT_SID`
- `CJ_PUBLISHER_ID`
- `RAKUTEN_SID`
- `SOVRN_API_SECRET_NOTE` - note only; Sovrn secret must live proxy-side, never on device

## Before Enabling `liveSearchEnabled`

1. Deploy proxy, recommended Cloudflare Workers.
2. Implement proxy endpoints:
   - `/amazon/search`
   - `/impact/search`
   - `/cj/search`
   - `/rakuten/search`
   - `/sovrn/search`
3. Fill `Secrets.xcconfig`.
4. Fill approved retailer tracking IDs in `RetailerConfig.json`.
5. Set `searchStatus` per retailer after approval and fixture validation.
6. Re-run adapter integration fixtures against one real response sample per network.
7. Confirm no scan photos, outfit memory, favorites, user identifiers, coordinates, or history are sent to any retailer or affiliate network.

## Proxy Endpoint Contract

All proxy endpoints accept GET query parameters derived from `ProductSearchQuery` only:

- `q`
- `retailer`
- `brand`
- `category`
- `color`
- `size`
- `gender`
- `minPrice`
- `maxPrice`
- `occasion`
- `onSaleOnly`
- `sort`

The app must never send:

- scan photos
- outfit images
- OutfitMemory contents
- saved favorites
- viewed product history
- dismissed product IDs
- user name
- user ID
- coordinates

## Response Shape Expectations

The iOS adapters are tested against local fixtures based on these response families:

- Amazon PA API: `ItemsResult.Items[]`
- Impact: `Items[]`
- CJ: `products[]`
- Rakuten: `item[]`
- Sovrn: `results[]`

Each endpoint must return enough fields to map into `AffiliateProduct`: stable ID, product name, retailer, brand when available, category/subcategory, image URL, outbound product URL, price when allowed, sale price when available, colors/tags when available.

## Compliance Checks

- Amazon stored/catalog prices must not render unless future approved live PA API terms allow it.
- All cards and detail surfaces must show `Sold and shipped by {Retailer}`.
- FTC affiliate disclosure must stay visible in Shopping and Store Search.
- Retailer-responsibility disclaimer must stay visible in Store Search and product surfaces.
- No checkout, cart, payment, order tracking, returns, or account features in the first release.
