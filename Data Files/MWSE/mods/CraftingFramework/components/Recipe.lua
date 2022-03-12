local Util = require("CraftingFramework.util.Util")
local Material = require("CraftingFramework.components.Material")
local Craftable = require("CraftingFramework.components.Craftable")
local SkillRequirement = require("CraftingFramework.components.SkillRequirement")
local CustomRequirement = require("CraftingFramework.components.CustomRequirement")
local Tool = require("CraftingFramework.components.Tool")
local config = require("CraftingFramework.config")

local MaterialRequirementSchema = {
    name = "MaterialRequirement",
    fields = {
        material = { type = "string", required = true },
        count = { type = "number", required = false, default = 1 }
    }
}

local ToolRequirementsSchema = {
    name = "ToolRequirements",
    fields = {
        tool = { type = "string", required = true },
        equipped = { type = "boolean", required = false },
        count = { type = "number", required = false },
        conditionPerUse = { type = "number", required = false }
    }
}

local Recipe = {
    schema = {
        name = "Recipe",
        fields = {
            id = { type = "string", required = false },
            description = { type = "string", required = false },
            craftable = { type = Craftable.schema, required = false },
            materials = { type = "table", childType = MaterialRequirementSchema, required = true },
            timeTaken = { type = "string", required = false },
            knownByDefault = { type = "boolean", required = false },
            customRequirements = { type = "table", childType = CustomRequirement.schema, required = false },
            skillRequirements = { type = "table", childType = SkillRequirement.schema, required = false },
            tools = { type = "table", childType = ToolRequirementsSchema, required = false },
            category = { type = "string", required = false },
            mesh = { type = "string", required = false},
        }
    }
}

Recipe.registeredRecipes = {}
function Recipe.getRecipe(id)
    return Recipe.registeredRecipes[id]
end

function Recipe:new(data)
    local recipe = table.copy(data, {})
    Util.validate(data, Recipe.schema)
    recipe.knownByDefault = data.knownByDefault or true
    --Flatten the API so craftable is just part of the
    local craftableFields = Craftable.schema.fields
    recipe.craftable = data.craftable or {}
    for field, _ in pairs(craftableFields) do
        if not recipe.craftable[field] then
            recipe.craftable[field] = data[field]
        end
    end

    recipe.id = data.id or data.craftable.id
    recipe.tools = data.tools or {}
    recipe.category = recipe.category or "Other"
    recipe.skillRequirements = Util.convertListTypes(data.skillRequirements, SkillRequirement) or {}
    recipe.customRequirements = Util.convertListTypes(data.customRequirements, CustomRequirement) or {}
    assert(recipe.id, "Validation Error: No id or craftable provided for Recipe")
    recipe.craftable = Craftable:new(recipe.craftable)
    setmetatable(recipe, self)
    self.__index = self
    Recipe.registeredRecipes[recipe.id] = recipe
    return recipe
end


function Recipe:learn()
    config.persistent.knownRecipes[self.id] = true
end

function Recipe:unlearn()
    self.knownByDefault = false
    config.persistent.knownRecipes[self.id] = nil
end

function Recipe:isKnown()
    if self.knownByDefault then return true end
    return config.persistent.knownRecipes[self.id]
end

function Recipe:craft()
    local materialsUsed = {}
    for _, materialReq in ipairs(self.materials) do
        local material = Material.getMaterial(materialReq.material)
        local remaining = materialReq.count
        for id, _ in pairs(material.ids) do
            materialsUsed[id] = materialsUsed[id] or 0

            local inInventory = mwscript.getItemCount{ reference = tes3.player, item = id}
            local numToRemove = math.min(inInventory, remaining)
            materialsUsed[id] = materialsUsed[id] + numToRemove
            tes3.removeItem{ reference = tes3.player, item = id, playSound = false, count = numToRemove}
            remaining = remaining - numToRemove
            if remaining == 0 then break end
        end
    end
    for _, toolReq in ipairs(self.tools) do
        local tool = Tool.getTool(toolReq.tool)
        if tool then
            tool:use(toolReq.conditionPerUse)
        end
    end

    self.craftable:craft(materialsUsed)
    --progress skills
    for _, skillRequirement in ipairs(self.skillRequirements) do
        skillRequirement:progressSkill()
    end
end

function Recipe:getItem()
    local id = self.craftable.placedObject or self.id
    if id then
        return tes3.getObject(id)
    end
end

function Recipe:getAverageSkillLevel()
    local total = 0
    local count = 0
    for _, skillRequirement in ipairs(self.skillRequirements) do
        total = total + skillRequirement.requirement
        count = count + 1
    end
    if count == 0 then return 0 end
    return total / count
end

function Recipe:hasMaterials()
    for _, materialReq in ipairs(self.materials) do
        local material = Material.getMaterial(materialReq.material)
        if not material then
            Util.log:error("Can not craft %s, required material '%s' has not been registered", self.id, materialReq.material)
            return false, "You do not have the required materials"
        end
        local numRequired = materialReq.count
        if not material:checkHasIngredient(numRequired) then
            return false, "You do not have the required materials"
        end
    end
    return true
end

function Recipe:meetsToolRequirements()
    for _, toolRequirement in ipairs(self.tools) do
        local tool = Tool.getTool(toolRequirement.tool)
        if not tool then
            Util.log:error("Can not craft %s, required tool '%s' has not been registered", self.id, tool.id)
            return false, "You do not have the required tools"
        end
        if not tool:hasTool(toolRequirement) then
            return false, "You do not have the required tools"
        end
    end
    return true
end

function Recipe:meetsSkillRequirements()
    for _, skillRequirement in ipairs(self.skillRequirements) do
        if not skillRequirement:check() then
            return false, "Your skill is not high enough"
        end
    end
    return true
end

function Recipe:meetsCustomRequirements()
    if self.customRequirements then
        for _, requirement in ipairs(self.customRequirements) do
            local meetsRequirements, reason = requirement:check()
            if not meetsRequirements then
                return false, reason
            end
        end
    end
    return true
end

function Recipe:meetsAllRequirements()
    local meetsCustomRequirements, reason = self:meetsCustomRequirements()
    if not meetsCustomRequirements then return false, reason end
    local hasMaterials, reason = self:hasMaterials()
    if not hasMaterials then return false, reason end
    local meetsToolRequirements, reason = self:meetsToolRequirements()
    if not meetsToolRequirements then return false, reason end
    local meetsSkillRequirements, reason = self:meetsSkillRequirements()
    if not meetsSkillRequirements then return false, reason end
    return true
end

return Recipe