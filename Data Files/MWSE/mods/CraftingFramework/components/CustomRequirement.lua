local Util = require("CraftingFramework.util.Util")
local config = require("CraftingFramework.config")

local CustomRequirement = {
    schema = {
        name = "CustomRequirement",
        fields = {
            getLabel = { type = "function",  required = true},
            check = { type = "function",  required = true},
            showInMenu = { type = "boolean", default = true, required = false},
        }
    }
}


--Constructor
function CustomRequirement:new(data)
    Util.validate(data, CustomRequirement.schema)
    setmetatable(data, self)
    self.__index = self
    return data
end

function CustomRequirement:getLabel()
    return nil
end

function CustomRequirement:check()
    return nil
end

return CustomRequirement