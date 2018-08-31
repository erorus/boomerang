local ADDON_NAME = "|cffffff66Boomerang|r"
local PriceCheck = function(...) return nil end
local origPostAuction = PostAuction
local blockingEnabled = true
local startupErrorMessage

-- If posting price < (suggested price * MIN_PRICE_FACTOR) then flag it as too low
local MIN_PRICE_FACTOR = 0.20

local floor = math.floor
local tonumber = tonumber

local function coins(money)
    local GOLD="ffd100"
    local SILVER="e6e6e6"
    local COPPER="c8602c"

    local GSC_3 = "%d|cff%sg|r %02d|cff%ss|r %02d|cff%sc|r"
    local GSC_2 = "%d|cff%sg|r %02d|cff%ss|r"

    money = floor(tonumber(money) or 0)
    local g = floor(money / 10000)
    local s = floor(money % 10000 / 100)
    local c = money % 100

    if (c > 0) then
        return GSC_3:format(g, GOLD, s, SILVER, c, COPPER)
    else
        return GSC_2:format(g, GOLD, s, SILVER)
    end
end

SLASH_BOOMERANG1 = '/boomerang'
function SlashCmdList.BOOMERANG(msg)
    if startupErrorMessage then
        print(ADDON_NAME .. ": " .. startupErrorMessage)

        return
    end

    blockingEnabled = not blockingEnabled
    if msg == 'on' then
        blockingEnabled = true
    elseif msg == 'off' then
        blockingEnabled = false
    end
    if blockingEnabled then
        print(ADDON_NAME .. ": Protection enabled.")
    else
        print(ADDON_NAME .. ": Protection disabled.")
    end
end

local function IsAddonEnabled(name)
    return GetAddOnEnableState(UnitName("player"), name) == 2 and select(4, GetAddOnInfo(name)) and true or false
end

local function GetCurrentAuctionItem()
    -- from Auctionator

    local auctionItemName = GetAuctionSellItemInfo();
    if (auctionItemName == nil) then
        return nil
    end

    local auctionItemLink = nil;

    -- only way to get sell itemlink that I can figure
    local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetAuctionSellItem();
    if (speciesID and speciesID > 0) then   -- if it's a battle pet, construct a fake battlepet link
        local battlePetID = 0   -- unfortunately we don't know it

        auctionItemLink = "|cffcccccc|Hbattlepet:"..speciesID..":"..level..":"..breedQuality..":"..maxHealth..":"..power..":"..speed..":"..battlePetID.."|h["..name.."]|h|r";
    else
        AtrScanningTooltip:SetAuctionSellItem();

        local name;
        name, auctionItemLink = AtrScanningTooltip:GetItem();
    end

    return auctionItemLink;
end

local function AuctionHook(...)
    local minBid, buyoutPrice, runTime, stackSize, numStacks = ...

    if (buyoutPrice == 0) then
        -- this has no buyout, bid only
        return origPostAuction(...)
    end

    local itemLink = GetCurrentAuctionItem();
    if (not itemLink) then
        print(ADDON_NAME .. ": Warning: Could not find auction item for this post attempt.");

        return origPostAuction(...)
    end

    local eachString = ""
    if (stackSize > 1) then
        eachString = " each"
    end

    local pricePer = floor(buyoutPrice / stackSize)
    local suggestedPrice, priceSource = PriceCheck(itemLink, pricePer)
    if (suggestedPrice) then
        local action = "Blocked"
        if (not blockingEnabled) then
            action = "Ignored"
        end

        print(ADDON_NAME .. ": " .. action .. " posting " .. itemLink .. " for " .. coins(pricePer) .. eachString .. ". "
                .. priceSource .. " suggests " .. coins(suggestedPrice));

        if (blockingEnabled) then
            return
        end
    end

    return origPostAuction(...)
end

local priceSources = 0

if (GetAuctionBuyout) then
    priceSources = priceSources + 1
    local prevPriceCheck = PriceCheck

    PriceCheck = function(itemLink, pricePer)
        local result = GetAuctionBuyout(itemLink)
        if (result and pricePer < (result * MIN_PRICE_FACTOR)) then
            return result, "GetAuctionBuyout"
        end

        return prevPriceCheck(itemLink, pricePer)
    end
end

if (IsAddonEnabled("Auctionator") and Atr_GetAuctionBuyout) then
    priceSources = priceSources + 1
    local prevPriceCheck = PriceCheck

    PriceCheck = function(itemLink, pricePer)
        local result = Atr_GetAuctionBuyout(itemLink)
        if (result and pricePer < (result * MIN_PRICE_FACTOR)) then
            return result, "Auctionator"
        end

        return prevPriceCheck(itemLink, pricePer)
    end
end

if (IsAddonEnabled("TradeSkillMaster") and TSMAPI_FOUR and TSMAPI_FOUR.CustomPrice and TSMAPI_FOUR.CustomPrice.GetItemPrice) then
    priceSources = priceSources + 1
    local prevPriceCheck = PriceCheck

    PriceCheck = function(itemLink, pricePer)
        local result = TSMAPI_FOUR.CustomPrice.GetItemPrice(itemLink, "DBMarket")
        if (result and pricePer < (result * MIN_PRICE_FACTOR)) then
            return result, "TradeSkillMaster"
        end

        return prevPriceCheck(itemLink, pricePer)
    end
end

if (IsAddonEnabled("TheUndermineJournal") and TUJMarketInfo) then
    priceSources = priceSources + 1
    local prevPriceCheck = PriceCheck

    local TUJ = {}
    PriceCheck = function(itemLink, pricePer)
        TUJMarketInfo(itemLink, TUJ)

        if (TUJ['market']) then
            if (TUJ['stddev'] > 0) then
                if (pricePer < (TUJ['market'] - TUJ['stddev'] * 2)) then
                    return TUJ['market'], "The Undermine Journal"
                end
            else
                if (pricePer < (TUJ['market'] * MIN_PRICE_FACTOR)) then
                    return TUJ['market'], "The Undermine Journal"
                end
            end
        end

        return prevPriceCheck(itemLink, pricePer)
    end
end

if not origPostAuction then
    startupErrorMessage = "Could not find PostAuction function, protection disabled!"
elseif priceSources == 0 then
    startupErrorMessage = "No price sources found (TUJ, TSM, Auctionator, Tekkub-compatible), protection disabled!"
end

if startupErrorMessage then
    print(ADDON_NAME .. ": " .. startupErrorMessage)
else
    PostAuction = AuctionHook
end
