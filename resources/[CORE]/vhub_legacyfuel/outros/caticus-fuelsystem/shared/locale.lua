Locale = Locale or {}

function Locale:new(settings)
    local self = {}
    self.phrases = settings.phrases or {}
    self.warnOnMissing = settings.warnOnMissing or false
    
    function self:t(key, params)
        local keys = {}
        for k in string.gmatch(key, "([^.]+)") do
            table.insert(keys, k)
        end
        
        local phrase = self.phrases
        for _, k in ipairs(keys) do
            if phrase[k] then
                phrase = phrase[k]
            else
                if self.warnOnMissing then
                    print("^3[Locale]^7 Missing translation key: " .. key)
                end
                return key
            end
        end
        
        if type(phrase) == "string" then
            if params then
                for k, v in pairs(params) do
                    phrase = string.gsub(phrase, "%%{" .. k .. "}", tostring(v))
                end
            end
            return phrase
        end
        
        return key
    end
    
    return self
end

-- Initialize Lang with empty phrases, will be populated by locale files
if not Lang then
    Lang = Locale:new({
        phrases = {},
        warnOnMissing = true
    })
end
