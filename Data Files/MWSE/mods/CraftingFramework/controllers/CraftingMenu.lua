local Material = require("CraftingFramework.components.Material")
local Recipe = require("CraftingFramework.components.Recipe")
local Util = require("CraftingFramework.util.Util")
local Tool = require("CraftingFramework.components.Tool")
local this = {}

local selectedRecipe
local currentRecipeList
local showCategories
local currentSorter
local currentFilter

local menuConfig = {
    menuWidth = 600,
    menuHeight = 800,
    previewHeight = 270,
    previewWidth= 270,
    previewYOffset = -200
}

local uiids = {
    titleBlock = tes3ui.registerID("Crafting_Menu_TitleBlock"),
    craftingMenu = tes3ui.registerID("CraftingFramework_Menu"),
    midBlock = tes3ui.registerID("Crafting_Menu_MidBlock"),
    previewBorder = tes3ui.registerID("Crafting_Menu_PreviewBorder"),
    previewBlock = tes3ui.registerID("Crafting_Menu_PreviewBlock"),
    nifPreviewBlock = tes3ui.registerID("Crafting_Menu_NifPreviewBlock"),
    imagePreviewBlock = tes3ui.registerID("Crafting_Menu_ImagePreviewBlock"),
    selectedItem = tes3ui.registerID("Crafting_Menu_SelectedResource"),
    nif = tes3ui.registerID("Crafting_Menu_NifPreview"),
    descriptionBlock = tes3ui.registerID("Crafting_Menu_DescriptionBlock"),
    buttonsBlock = tes3ui.registerID("Crafting_Menu_ButtonsBlock"),
    recipeListBlock = tes3ui.registerID("Crafting_Menu_recipeListBlock"),
    previewPane = tes3ui.registerID("Crafting_Menu_PreviewPane"),
    previewName = tes3ui.registerID("Crafting_Menu_PreviewName"),
    previewDescription = tes3ui.registerID("Crafting_Menu_PreviewDescription"),
    materialRequirementsPane = tes3ui.registerID("Crafting_Menu_MaterialRequirementsPane"),
    materialRequirementsBlock = tes3ui.registerID("Crafting_Menu_MaterialRequirementsBlock"),
    skillRequirementsBlock = tes3ui.registerID("Crafting_Menu_SkillRequirementsBlock"),
    skillRequirementsPane = tes3ui.registerID("Crafting_Menu_SkillsPane"),
    customRequirementsBlock = tes3ui.registerID("Crafting_Menu_CustomRequirementsBlock"),
    customRequirementsPane = tes3ui.registerID("Crafting_Menu_CustomRequirementsPane"),
    toolRequirementsPane = tes3ui.registerID("Crafting_Menu_ToolsPane"),
    toolRequirementsBlock = tes3ui.registerID("Crafting_Menu_ToolsContainer"),
    createItemButton = tes3ui.registerID("Crafting_Menu_CreateItemButton"),
    unlockPackButton = tes3ui.registerID("Crafting_Menu_UnlockPackButton"),
    cancelButton = tes3ui.registerID("Crafting_Menu_CancelButton"),
}
local m1 = tes3matrix33.new()
local m2 = tes3matrix33.new()


function this.closeMenu()
    Util.log:debug("Closing Menu")
    local menu = tes3ui.findMenu(uiids.craftingMenu)
    if menu then
        Util.log:debug("Destroying Menu")
        menu:destroy()
        tes3ui.leaveMenuMode()
        selectedRecipe = nil
        currentRecipeList = nil

    else
        Util.log:error("Can't find menu!!!")
    end
end

function this.craftItem(button)
    selectedRecipe:craft()
    button.widget.state = 2
    button.disabled = true
    if not selectedRecipe then return end
    if selectedRecipe.craftable.uncarryable then
        this.closeMenu()
    else
        this.updateMenu()
    end
end


local sorters = {}
sorters.name = {
    name = "Name",
    sorter = function(a, b)
        return a.craftable:getName() < b.craftable:getName()
    end,
    nextSorter = "skill",
}
sorters.skill = {
    name = "Difficulty",
    sorter = function(a, b)
        local aSkill = a:getAverageSkillLevel()
        local bSkill = b:getAverageSkillLevel()
        if aSkill == bSkill then
            return sorters.name.sorter(a, b)
        else
            return aSkill < bSkill
        end
    end,
    nextSorter = "canCraft",
}
sorters.canCraft = {
    name = "Can Craft",
    sorter = function(a, b)
        local aMeetsRequirements = a:meetsAllRequirements() and 1 or 0
        local bMeetsRequirements = b:meetsAllRequirements() and 1 or 0
        if aMeetsRequirements == bMeetsRequirements then
            return sorters.name.sorter(a, b)
        else
            return aMeetsRequirements > bMeetsRequirements
        end
    end,
    nextSorter = "name",
}

local filters = {}
filters.all = {
    name = "All",
    filter = function(recipe)
        return true
    end,
    nextFilter = "canCraft"
}
filters.canCraft = {
    name = "Can Craft",
    filter = function(recipe)
        return recipe:meetsAllRequirements()
    end,
    nextFilter = "hasMaterials"
}
filters.hasMaterials = {
    name = "Materials",
    filter = function(recipe)
        return recipe:hasMaterials() and recipe:meetsToolRequirements()
    end,
    nextFilter = "skill"
}
filters.skill = {
    name = "Skill",
    filter = function(recipe)
        return recipe:meetsSkillRequirements()
    end,
    nextFilter = "all"
}



local menuButtons = {
    {
        id = "Ashfall_Button_Filter",
        name = function()
            return "Filter: " .. filters[currentFilter].name
        end,
        callback = function(_)
            local nextFilter = filters[currentFilter].nextFilter
            Util.log:debug("Next Filter: " .. nextFilter)
            currentFilter = nextFilter
            this.populateRecipeList()
        end
    },
    {
        id = tes3ui.registerID("Ashfall_Button_Sort"),
        name = function()
            return "Sort: " .. sorters[currentSorter].name
        end,
        callback = function(_)
            local nextSorter = sorters[currentSorter].nextSorter
            Util.log:debug("nextSorter: %s", nextSorter)
            currentSorter = nextSorter
            this.populateRecipeList()
        end
    },
    {
        id = tes3ui.registerID("Ashfall_Button_ShowCategories"),
        name = function()
            return "Categories: " .. (showCategories and "Visible" or "Hidden")
        end,
        callback = function(_)
            showCategories = not showCategories
            this.populateRecipeList()
        end
    },
    {
        id = tes3ui.registerID("Ashfall_Button_CraftItem"),
        name = function() return "Craft" end,
        callback = function(button)
            this.craftItem(button)
        end,
        requirements = function()
            return selectedRecipe:meetsAllRequirements()
        end
    },
}


function this.removeCollision(sceneNode)
    for node in Util.traverseRoots{sceneNode} do
        if node:isInstanceOfType(tes3.niType.RootCollisionNode) then
            node.appCulled = true
        end
    end
end


function this.toggleButtonDisabled(button, isVisible, isDisabled)
    button.visible = isVisible
    button.widget.state = isDisabled and 2 or 1
    button.disabled = isDisabled
end

function this.createToolTooltip(tool, toolReq)
    Util.log:debug("ids: %s", json.encode(tool.ids, {indent = true}))
    local tooltip = tes3ui.createTooltipMenu()
    local outerBlock = tooltip:createBlock()
    outerBlock.flowDirection = "top_to_bottom"
    outerBlock.paddingTop = 6
    outerBlock.paddingBottom = 12
    outerBlock.paddingLeft = 6
    outerBlock.paddingRight = 6
    outerBlock.maxWidth = 300
    outerBlock.autoWidth = true
    outerBlock.autoHeight = true
    outerBlock.childAlignX = 0.5

    local header =  outerBlock:createLabel{ text = tool.name}
    header.color = tes3ui.getPalette("header_color")

    for id, _ in pairs(tool.ids) do
        Util.log:debug("Tool Id: %s", id)
        local item = tes3.getObject(id)
        if item then
            local itemCount = mwscript.getItemCount{ reference = tes3.player, item = item }
            local block = outerBlock:createBlock{}
            block.flowDirection = "left_to_right"
            block.autoHeight = true
            block.autoWidth = true
            block.childAlignX = 0.5

            block:createImage{path=("icons\\" .. item.icon)}
            local nameText = string.format("%s (%G)", item.name, itemCount)

            if toolReq.equipped then
                if Tool.checkToolEquipped(item, toolReq) then
                    nameText = string.format("%s (Equipped)", item.name)
                else
                    nameText = string.format("%s (Not Equipped)", item.name)
                end
            end
            if itemCount > 0 and not Tool.checkToolCondition(item) then
                nameText = string.format("%s (Broken)", item.name)
            end
            local textLabel = block:createLabel{ text = nameText}
            textLabel.borderAllSides = 4

            if not Tool.checkToolRequirements(id, toolReq) then
                textLabel.color = tes3ui.getPalette("disabled_color")
            end
        else
            Util.log:error("Could not find item %s", id)
        end
    end
end

function this.createToolLabel(toolReq, parentList)
    local tool = Tool.getTool(toolReq.tool)
    if tool then
        local requirementText = string.format("%s x %G", tool.name, (toolReq.count or 1) )
        if toolReq.equipped then
            if tool:checkToolEquipped(toolReq) then
                requirementText = string.format("%s (Equipped)", tool.name)
            else
                requirementText = string.format("%s (Not Equipped)", tool.name)
            end
        end
        if tool:hasToolCondition(toolReq) == false then
            requirementText = string.format("%s (Broken)", tool.name)
        end

        local requirement = parentList:createLabel()
        requirement.borderAllSides = 2
        requirement.text = requirementText

        requirement:register("help", function()
            this.createToolTooltip(tool, toolReq)
        end)

        if tool:hasTool(toolReq) then
            requirement.color = tes3ui.getPalette("normal_color")
        else
            requirement.color = tes3ui.getPalette("disabled_color")
        end
    end
end

function this.updateToolsPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end
    local toolRequirementsBlock = craftingMenu:findChild(uiids.toolRequirementsBlock)
    local list = craftingMenu:findChild(uiids.toolRequirementsPane)
    list:getContentElement():destroyChildren()
    if #recipe.tools < 1 then
        toolRequirementsBlock.visible = false
    else
        toolRequirementsBlock.visible = true
        for _, toolReq in ipairs(recipe.tools) do
            this.createToolLabel(toolReq, list)
        end
    end
end

function this.createCustomRequirementLabel(customRequirement, list)
    local requirement = list:createLabel()
    requirement.borderAllSides = 2
    requirement.text = customRequirement:getLabel()
    local meetsRequirements, reason = customRequirement:check()
    if meetsRequirements then
        requirement.color = tes3ui.getPalette("normal_color")
    else
        requirement.color = tes3ui.getPalette("disabled_color")
    end
    if reason then
        --create tooltip
        requirement:register("help", function()
            local tooltip = tes3ui.createTooltipMenu()
            tooltip:createLabel{ text = reason }
        end)
    end
end

function this.updateCustomRequirementsPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end
    local customRequirementsBlock = craftingMenu:findChild(uiids.customRequirementsBlock)
    local list = craftingMenu:findChild(uiids.customRequirementsPane)
    list:getContentElement():destroyChildren()
    local customRequirements = recipe.customRequirements
    if #customRequirements < 1 or customRequirements.showInMenu == false then
        customRequirementsBlock.visible = false
    else
        customRequirementsBlock.visible = true
        for _, customReq in ipairs(customRequirements) do
            this.createCustomRequirementLabel(customReq, list)
        end
    end
end

function this.createSkillTooltip(skillReq)
    local name = skillReq:getSkillName()
    local tooltip = tes3ui.createTooltipMenu()
    local outerBlock = tooltip:createBlock()
    outerBlock.flowDirection = "top_to_bottom"
    outerBlock.paddingTop = 6
    outerBlock.paddingBottom = 12
    outerBlock.paddingLeft = 6
    outerBlock.paddingRight = 6
    outerBlock.maxWidth = 300
    outerBlock.autoWidth = true
    outerBlock.autoHeight = true
    outerBlock.childAlignX = 0.5
    local header =  outerBlock:createLabel{ text = name}
    header.color = tes3ui.getPalette("header_color")

    local current = skillReq:getCurrent()
    local required = skillReq.requirement
    outerBlock:createLabel{
        text = string.format("Current: %s", current)
    }
    outerBlock:createLabel{
        text = string.format("Required: %s", required)
    }
end

function this.createSkillLabel(skillReq, parentList)
    local current = skillReq:getCurrent()
    local skillText = string.format("%s: %s/%s",
        skillReq:getSkillName(),
        current, skillReq.
        requirement)
    local requirement = parentList:createLabel()
    requirement.borderAllSides = 2
    requirement.text = skillText
    requirement:register("help", function()
        this.createSkillTooltip(skillReq)
    end)
    if skillReq:check() then
        requirement.color = tes3ui.getPalette("normal_color")
    else
        requirement.color = tes3ui.getPalette("disabled_color")
    end
end


function this.updateSkillsRequirementsPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end

    local skillRequirementsPane = craftingMenu:findChild(uiids.skillRequirementsPane)
    local skillsBlock = craftingMenu:findChild(uiids.skillRequirementsBlock)
    skillRequirementsPane:getContentElement():destroyChildren()
    if #recipe.skillRequirements < 1 then
        skillsBlock.visible = false
    else
        skillsBlock.visible = true
        for _, skillReq in ipairs(recipe.skillRequirements) do
            this.createSkillLabel(skillReq, skillRequirementsPane)
        end
    end
end

function this.createMaterialTooltip(material)
    local name = material:getName()
    local tooltip = tes3ui.createTooltipMenu()
    local outerBlock = tooltip:createBlock()
    outerBlock.flowDirection = "top_to_bottom"
    outerBlock.paddingTop = 6
    outerBlock.paddingBottom = 12
    outerBlock.paddingLeft = 6
    outerBlock.paddingRight = 6
    outerBlock.maxWidth = 300
    outerBlock.autoWidth = true
    outerBlock.autoHeight = true
    outerBlock.childAlignX = 0.5
    local header =  outerBlock:createLabel{ text = name}
    header.color = tes3ui.getPalette("header_color")
    for id, _ in pairs(material.ids) do
        local item = tes3.getObject(id)
        if item then
            local itemCount = mwscript.getItemCount{ reference = tes3.player, item = item }
            local block = outerBlock:createBlock{}
            block.flowDirection = "left_to_right"
            block.autoHeight = true
            block.autoWidth = true
            block.childAlignX = 0.5

            block:createImage{path=("icons\\" .. item.icon)}
            local text = string.format("%s (%G)", item.name, itemCount)
            local textLabel = block:createLabel{ text = text}
            textLabel.borderAllSides = 4

            if itemCount <= 0 then
                textLabel.color = tes3ui.getPalette("disabled_color")
            end
        end
    end
end

function this.createMaterialButton(materialReq, list)
    local material = Material.getMaterial(materialReq.material)
    local materialText = string.format("%s x %G", material:getName(), materialReq.count )
    local requirement = list:createLabel()
    requirement.borderAllSides = 2
    requirement.text = materialText
    requirement:register("help", function()
        this.createMaterialTooltip(material)
    end)
    if material:checkHasIngredient(materialReq.count) then
        requirement.color = tes3ui.getPalette("normal_color")
    else
        requirement.color = tes3ui.getPalette("disabled_color")
    end
end

function this.updateMaterialsRequirementsPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end

    local list = craftingMenu:findChild(uiids.materialRequirementsPane)
    list:getContentElement():destroyChildren()
    for _, materialReq in ipairs(recipe.materials) do
        this.createMaterialButton(materialReq, list)
    end
end

function this.updateDescriptionPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end

    local descriptionBlock = craftingMenu:findChild(uiids.descriptionBlock)
    if not descriptionBlock then return end
    descriptionBlock:destroyChildren()

    local selectedItemLabel = descriptionBlock:createLabel{ id = uiids.selectedItem }
    selectedItemLabel.autoWidth = true
    selectedItemLabel.autoHeight = true
    selectedItemLabel.color = tes3ui.getPalette("header_color")
    selectedItemLabel.text = recipe.craftable:getNameWithCount()
    selectedItemLabel:register("help", function()
        tes3ui.createTooltipMenu{ item = recipe.craftable.id }
    end)

    local previewDescription = descriptionBlock:createLabel{ id = uiids.previewDescription }
    previewDescription.wrapText = true
    previewDescription.text = recipe.description or ""
    previewDescription:register("help", function()
        tes3ui.createTooltipMenu{ item = recipe.craftable.id }
    end)
end

function this.updatePreviewPane(recipe)
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end
    local item = recipe:getItem()
    if item then
        --nifPreviewBLock
        local nifPreviewBlock = craftingMenu:findChild(uiids.nifPreviewBlock)
        if nifPreviewBlock then
            nifPreviewBlock:destroyChildren()
            local mesh = recipe.mesh or item.mesh
            local nif = nifPreviewBlock:createNif{ id = uiids.nif, path = mesh}
            if not nif then return end
            --nif.scaleMode = true
            craftingMenu:updateLayout()

            local node = nif.sceneNode
            Util.removeLight(node)
            this.removeCollision(node)
            node:update()

            --get size from bounding box
            local maxDimension
            local bb = node:createBoundingBox(node.scale)
            local height = bb.max.z - bb.min.z
            local width = bb.max.y - bb.min.y
            local depth = bb.max.x - bb.min.x
            maxDimension = math.max(width, depth, height)

            local targetHeight = 140
            node.scale = targetHeight / maxDimension

            local lowestPoint = bb.min.z * node.scale
            node.translation.z = node.translation.z - lowestPoint

            do --add properties
                local vertexColorProperty = niVertexColorProperty.new()
                vertexColorProperty.name = "vcol yo"
                vertexColorProperty.source = 2
                node:attachProperty(vertexColorProperty)

                local zBufferProperty = niZBufferProperty.new()
                zBufferProperty.name = "zbuf yo"
                zBufferProperty:setFlag(true, 0)
                zBufferProperty:setFlag(true, 1)
                node:attachProperty(zBufferProperty)
            end

            m1:toRotationX(math.rad(-15))
            m2:toRotationZ(math.rad(180))
            node.rotation = node.rotation * m1:copy() * m2:copy()


            node.appCulled = false
            node:updateProperties()
            node:update()
            nifPreviewBlock:updateLayout()
        end
    end
    --updateBuyButtons()
end
function this.updateButtons()
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end
    for _, buttonConf in ipairs(menuButtons) do
        local button = craftingMenu:findChild(buttonConf.id)

        if buttonConf.requirements and buttonConf.requirements()== false then
            this.toggleButtonDisabled(button, true, true)
            button:register("help", function()
                local tooltip = tes3ui.createTooltipMenu()
                local _, reason = buttonConf.requirements()
                tooltip:createLabel{ text = reason }
            end)
        else
            this.toggleButtonDisabled(button, true, false)
            button:register("mouseClick", function()
                buttonConf.callback(button)
                button.text = buttonConf.name()
            end)
        end
    end
end

function this.updateSidebar()
    this.updatePreviewPane(selectedRecipe)
    this.updateDescriptionPane(selectedRecipe)
    this.updateCustomRequirementsPane(selectedRecipe)
    this.updateSkillsRequirementsPane(selectedRecipe)
    this.updateMaterialsRequirementsPane(selectedRecipe)
    this.updateToolsPane(selectedRecipe)
end

function this.updateMenu()
    this.populateRecipeList()
    this.updateSidebar()
    this.updateButtons()
end


function this.populateCategoryList(recipes, list)
    table.sort(recipes, sorters[currentSorter].sorter)
    for _, recipe in ipairs(recipes) do
        if recipe:isKnown() and filters[currentFilter].filter(recipe) then
            local button = list:createTextSelect({ id = string.format("Button_%s", recipe.id)})
            local thisRecipeId = recipe.id
            local buttonCallback = function()
                selectedRecipe = Recipe.getRecipe(thisRecipeId)
                this.updateSidebar()
                this.updateButtons()
            end
            button:register("mouseClick", buttonCallback)
            button.borderAllSides = 2
            button.text = "- " .. recipe.craftable:getName()
            local canCraft = recipe:meetsAllRequirements()
            if not canCraft then
                button.color = tes3ui.getPalette("disabled_color")
                button.widget.idle = tes3ui.getPalette("disabled_color")
            end
        end
    end
end

function this.createCategoryBlock(category, parent)
    local block = parent:createBlock{}
    block.flowDirection = "top_to_bottom"
    block.autoHeight = true
    block.widthProportional = 1.0
    block.paddingAllSides = 2
    local headerText = string.format("[-] %s", category.name)
    local header = block:createTextSelect{ text = headerText}
    header.borderAllSides = 2
    local recipeBlock = this.createRecipeBlock(block)
    this.populateCategoryList(category.recipes, recipeBlock)
    local function setCategoryVisible()
        if category.visible then
            recipeBlock.visible = true
            header.text = string.format("[-] %s", category.name)
        else
            recipeBlock.visible = false
            header.text = string.format("[+] %s", category.name)
        end
        if #recipeBlock.children == 0 then
            header.widget.idle = tes3ui.getPalette("disabled_color")
        else
            header.widget.idle = tes3ui.getPalette("normal_color")
        end
    end
    header:register("mouseClick", function()
        category.visible = not category.visible
        setCategoryVisible()
    end)
    setCategoryVisible()
end

local currentCategories
function this.updateCategoriesList()
    for _, category in pairs(currentCategories) do
        Util.log:debug("Clearing recipes for %s", category.name)
        category.recipes = {}
    end

    for _, recipe in pairs(currentRecipeList) do
        local category = recipe.category
        if not currentCategories[category] then
            Util.log:debug("Category %s doesn't exist yet", category)
            currentCategories[category] = {
                name = category,
                recipes = {},
                visible = true,
            }
        end
        table.insert(currentCategories[recipe.category].recipes, recipe)
    end

    return currentCategories
end

function this.populateRecipeList()
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if not craftingMenu then return end
    local parent = craftingMenu:findChild(uiids.recipeListBlock)
    parent:destroyChildren()
    local title = parent:createLabel()
    title.color = tes3ui.getPalette("header_color")
    title.text = "Recipes:"

    local scrollBar = parent:createVerticalScrollPane()
    scrollBar.heightProportional = 1.0
    scrollBar.widthProportional = 1.0
    scrollBar.borderTop = 4

    this.updateCategoriesList()
    local sortedList = {}
    for _, category in pairs(currentCategories) do
        table.insert(sortedList, category)
    end
    table.sort(sortedList, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    if #sortedList > 1 and showCategories then
        for _, category in pairs(sortedList) do
            this.createCategoryBlock(category, scrollBar)
        end
    else
        this.populateCategoryList(currentRecipeList, scrollBar)
    end
end


function this.rotateNif(e)
    local menu = tes3ui.findMenu(uiids.craftingMenu)
    if not menu then
        event.unregister("enterFrame", this.rotateNif)
        return
    end
    local nif = menu:findChild(uiids.nif)
    if nif and nif.sceneNode then
        local node = nif.sceneNode
        m2:toRotationZ(math.rad(15) * e.delta)
        node.rotation = node.rotation * m2
        node:update()
    end
end

function this.resourceSorter(a, b)
	return a.name:lower() < b.name:lower()
end

function this.createPreviewPane(parent)
    local previewBorder = parent:createThinBorder{ id = uiids.previewBorder }
    --previewBorder.width = menuConfig.previewWidth
    previewBorder.flowDirection = "top_to_bottom"
    previewBorder.widthProportional= 1
    previewBorder.autoHeight = true
    previewBorder.childAlignX = 0.5
    --previewBorder.absolutePosAlignX = 0


    local nifPreviewBlock = previewBorder:createBlock{ id = uiids.nifPreviewBlock }
    --nifPreviewBlock.width = menuConfig.previewWidth
    nifPreviewBlock.width = menuConfig.previewWidth
    nifPreviewBlock.height = menuConfig.previewHeight

    nifPreviewBlock.childOffsetX = menuConfig.previewWidth/2
    nifPreviewBlock.childOffsetY = menuConfig.previewYOffset
    nifPreviewBlock.paddingAllSides = 2
end

function this.createLeftToRightBlock(parent)
    local block = parent:createBlock()
    block.widthProportional = 1.0
    block.heightProportional = 1.0
    block.flowDirection = "left_to_right"
    return block
end

function this.createTopToBottomBlock(parent)
    local block = parent:createBlock()
    block.widthProportional = 1.0
    block.heightProportional = 1.0
    block.flowDirection = "top_to_bottom"
    return block
end

function this.createTitle(block, titleName)
    local title = block:createLabel{ }
    title.text = titleName
    title.color = tes3ui.getPalette("header_color")
    return title
end

function this.createTitleBlock(parent, title)
    local titleBlock = parent:createBlock{ id = uiids.titleBlock }
    titleBlock.flowDirection = "top_to_bottom"
    titleBlock.childAlignX = 0.5
    titleBlock.autoHeight = true
    titleBlock.widthProportional = 1.0
    titleBlock.borderBottom = 10
    this.createTitle(titleBlock, title)
    return titleBlock
end

function this.createRecipeBlock(parent)
    local recipeListBlock = parent:findChild(uiids.recipeListBlock)
    if recipeListBlock then recipeListBlock:destroy() end
    recipeListBlock = parent:createBlock({ id = uiids.recipeListBlock})
    recipeListBlock.borderAllSides = 2
    recipeListBlock.widthProportional = 1.0
    recipeListBlock.autoHeight = true
    recipeListBlock.flowDirection = "top_to_bottom"
    return recipeListBlock
end

function this.createRecipeList(parent)
    local block = parent:createThinBorder{ id = uiids.recipeListBlock}
    block.flowDirection = "top_to_bottom"
    block.paddingAllSides = 10
    block.widthProportional = 1.0
    block.heightProportional = 1.0
    return block
end

function this.createDescriptionPane(parent)
    local descriptionBlock = parent:createThinBorder{ id = uiids.descriptionBlock}
    descriptionBlock.flowDirection = "top_to_bottom"
    descriptionBlock.paddingAllSides = 10
    descriptionBlock.widthProportional = 1.0
    descriptionBlock.autoHeight = true
end

function this.createRequirementsPane(parent, name, blockId, paneId)
    local block = parent:createThinBorder{ id = blockId }
    block.flowDirection = "top_to_bottom"
    block.paddingAllSides = 10
    block.widthProportional = 1.0
    block.autoHeight = true

    local title = block:createLabel()
    title.color = tes3ui.getPalette("header_color")
    title.text = name

    local requirementsPane = block:createBlock({ id = paneId})
    requirementsPane.borderTop = 4
    requirementsPane.widthProportional = 1.0
    requirementsPane.autoHeight = true
end

function this.createCustomRequirementsPane(parent)
    this.createRequirementsPane(
        parent,
        "Requirements:",
        uiids.customRequirementsBlock,
        uiids.customRequirementsPane
    )
end

function this.createSkillRequirementsPane(parent)
    this.createRequirementsPane(
        parent,
        "Skills:",
        uiids.skillRequirementsBlock,
        uiids.skillRequirementsPane
    )
end

function this.createToolsPane(parent)
    this.createRequirementsPane(
        parent,
        "Tools:",
        uiids.toolRequirementsBlock,
        uiids.toolRequirementsPane
    )
end

function this.createMaterialRequirementsPane(parent)
    local block = parent:createThinBorder{ id = uiids.materialRequirementsBlock }
    block.flowDirection = "top_to_bottom"
    block.paddingAllSides = 10
    block.widthProportional = 1.0
    block.heightProportional = 1.0

    local title = block:createLabel()
    title.color = tes3ui.getPalette("header_color")
    title.text = "Materials:"

    local skillRequirementsPane = block:createVerticalScrollPane({ id = uiids.materialRequirementsPane})
    skillRequirementsPane.borderTop = 4
    skillRequirementsPane.widthProportional = 1.0
    skillRequirementsPane.heightProportional = 1.0
end

function this.createMenuButtonBlock(parent)
    local buttonsBlock = parent:createBlock{ id = uiids.buttonsBlock}
    buttonsBlock.autoHeight = true
    buttonsBlock.widthProportional = 1.0
    buttonsBlock.childAlignX = 1.0
    --buttonsBlock.absolutePosAlignX = 1
    --buttonsBlock.absolutePosAlignY = 1.0
    return buttonsBlock
end

function this.addMenuButtons(parent)
    for _, buttonConf in ipairs(menuButtons) do
        local button = parent:createButton({ id = buttonConf.id})
        button.text = buttonConf.name()
        button.borderLeft = 0
    end
end

function this.openMenu(menuActivator)
    local title = menuActivator.name
    local recipeList = menuActivator.recipes
    selectedRecipe = selectedRecipe or recipeList[1]
    currentRecipeList = menuActivator.recipes
    currentCategories = {}
    currentFilter = menuActivator.defaultFilter
    currentSorter = menuActivator.defaultSort
    showCategories = menuActivator.defaultShowCategories


    tes3.playSound{sound="Menu Click", reference=tes3.player}
    local craftingMenu = tes3ui.findMenu(uiids.craftingMenu)
    if craftingMenu then craftingMenu:destroy() end
    craftingMenu = tes3ui.createMenu{ id = uiids.craftingMenu, fixedFrame = true }
    craftingMenu.minWidth = menuConfig.menuWidth
    craftingMenu.minHeight = menuConfig.menuHeight

    --"Bushcrafting"
    this.createTitleBlock(craftingMenu, title)

    --Left to Right block. Recipe list on the left, results on the right
    local outerBlock = this.createLeftToRightBlock(craftingMenu)

    --recipes on the left
    local recipeBlock = this.createRecipeList(outerBlock)
    recipeBlock.widthProportional = 0.9

    --Results on the right, consisting of a preview pane, description, and requirements list
    local resultsBlock = this.createTopToBottomBlock(outerBlock)
    resultsBlock.widthProportional = 1.1
    this.createPreviewPane(resultsBlock)
    this.createDescriptionPane(resultsBlock)
    this.createCustomRequirementsPane(resultsBlock)
    this.createToolsPane(resultsBlock)
    this.createSkillRequirementsPane(resultsBlock)
    this.createMaterialRequirementsPane(resultsBlock)

    --Craft and Cancel buttons on the bottom
    local menuButtonBlock = this.createMenuButtonBlock(craftingMenu)
    this.addMenuButtons(menuButtonBlock)
    this.updateButtons()

    local closeButton = menuButtonBlock:createButton({ id = uiids.cancelButton})
    closeButton.text = "Cancel"
    closeButton.borderLeft = 0
    closeButton:register("mouseClick", this.closeMenu)



    this.updateMenu()

    craftingMenu:updateLayout()
    tes3ui.enterMenuMode(uiids.craftingMenu)
    event.unregister("enterFrame", this.rotateNif)
    event.register("enterFrame", this.rotateNif)
end

local RightClickMenuExit = include("mer.RightClickMenuExit")
if RightClickMenuExit then
    Util.log:debug("Registering Crafting Menu Exit button")
    RightClickMenuExit.registerMenu{
        menuId = uiids.craftingMenu,
        buttonId = uiids.cancelButton
    }
end

return this