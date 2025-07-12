local api = require('api')
local ui = require('set_swap/ui')

local set_swap = {
  name = "Set Swap",
  version = "1.0.0",
  author = "Winterflame",
  desc = "Quickly change your equipped gear set."
}

local mainCanvas
local addNewSetCanvas
local settings
local enqueuedItems = {}
local isProcessingEquip = false
local betweenItemDelay = 100 -- Minimum delay between equip attempts in milliseconds
local retryDelay = 50       -- Minimum delay between equip attempts in milliseconds
local maxRetries = 1       -- Maximum number of retries for an item
local gearSetButtons = {}
local addSetButton
local widgetCounter = 0

local processNextEquip -- forward declaration

local function getUniqueWidgetId(prefix)
  widgetCounter = widgetCounter + 1
  return prefix .. "_" .. widgetCounter .. "_" .. tostring(api.Time:GetUiMsec())
end

local function safeDestroyWidget(widget, widgetName)
  if widget then
    widget:Show(false)
    -- widget:Destroy()
    return nil
  end
  return nil
end

local function equipTitle()
end

local function equipBagItem(slot, equipmentSlot)
  local isAlt = false
  if equipmentSlot == 13 or equipmentSlot == 11 or equipmentSlot == 17 then
    isAlt = true
  end

  api.Bag:EquipBagItem(slot, isAlt)
end

-- Add retry tracking for re-enqueued items
local function enqueueItemEquip(item, bagSlot, equipmentSlot, retryCount)
  if not item or not bagSlot then
    return
  end

  local itemToEquip = {
    bagSlot = bagSlot,
    item = item,
    equipmentSlot = equipmentSlot,
    retryCount = retryCount or 0
  }

  table.insert(enqueuedItems, itemToEquip)
end

local enqueueLoadoutEquipment = function(loadout)
  local maxBagSlots = 150
  local loadoutItems = #loadout.gear

  for loadoutItemIndex = 1, loadoutItems do
    local loadoutItem = loadout.gear[loadoutItemIndex]
    local itemName = loadoutItem.name
    local itemGrade = loadoutItem.grade
    local equipmentSlot = loadoutItem.slot

    for bagSlot = 1, maxBagSlots do
      local bagItem = api.Bag:GetBagItemInfo(1, bagSlot)
      if bagItem and bagItem.name == itemName and bagItem.itemGrade == itemGrade then
        enqueueItemEquip(bagItem, bagSlot, equipmentSlot, 0)
        break
      end
    end
  end

  -- Start processing if not already
  if not isProcessingEquip then
    processNextEquip()
  end
end

local function disableAllGearSetButtons()
  for _, btn in ipairs(gearSetButtons) do
    if btn then
      btn:Enable(false)
    end
  end
end

local function enableAllGearSetButtons()
  for _, btn in ipairs(gearSetButtons) do
    if btn then
      btn:Enable(true)
    end
  end
end

local function renderGearSetUI()
  -- Destroy old buttons with proper cleanup
  for i, btn in ipairs(gearSetButtons) do
    gearSetButtons[i] = safeDestroyWidget(btn, "gearSetButton_" .. i)
  end
  gearSetButtons = {}

  -- Destroy add button
  addSetButton = safeDestroyWidget(addSetButton, "addSetButton")

  -- Destroy old mainCanvas if it exists
  if mainCanvas then
    mainCanvas:Show(false)
    mainCanvas = nil
  end

  -- Recreate mainCanvas with unique ID
  local canvas_x = settings.x or 200
  local canvas_y = settings.y or 40
  local canvasId = getUniqueWidgetId("setSwapCanvas")

  mainCanvas = api.Interface:CreateEmptyWindow(canvasId, "UIParent")
  mainCanvas.background = mainCanvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  mainCanvas.background:SetTextureInfo("bg_quest")
  mainCanvas.background:SetColor(0, 0, 0, 0.6)
  mainCanvas.background:AddAnchor("TOPLEFT", mainCanvas, 0, 0)
  mainCanvas.background:AddAnchor("BOTTOMRIGHT", mainCanvas, 0, 0)
  mainCanvas:AddAnchor("TOPLEFT", "UIParent", canvas_x, canvas_y)

  -- Set up drag handlers
  function mainCanvas:OnDragStart()
    if api.Input:IsShiftKeyDown() then
      mainCanvas:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
  end

  mainCanvas:SetHandler("OnDragStart", mainCanvas.OnDragStart)

  function mainCanvas:OnDragStop()
    local current_x, current_y = mainCanvas:GetOffset()
    settings.x = current_x
    settings.y = current_y
    api.SaveSettings()
    mainCanvas:StopMovingOrSizing()
    api.Cursor:ClearCursor()
  end

  mainCanvas:SetHandler("OnDragStop", mainCanvas.OnDragStop)

  -- Canvas and button layout parameters
  local baseCanvasWidth = 90
  local baseCanvasHeight = 40
  local buttonBaseWidth = 70  -- Initial width, will be adjusted by skin handler
  local buttonGap = 5         -- Gap between gear set buttons
  local leftPadding = 9
  local rightPadding = 9
  local addButtonExtraGap = 10

  local numGearSets = settings.gear_sets and #settings.gear_sets or 0

  -- Set initial canvas size (will be updated after buttons are created)
  mainCanvas:SetExtent(baseCanvasWidth, baseCanvasHeight)

  local dynamicButtonsWidth = 0

  -- Recreate gear set buttons with unique IDs
  for i, gear_set in ipairs(settings.gear_sets) do
    local buttonId = getUniqueWidgetId("gearSetButton")

    -- Calculate button X position using accumulated width
    local buttonX = leftPadding + dynamicButtonsWidth

    local setBtn = ui.createButton(
      buttonId,
      mainCanvas,
      gear_set.name,
      buttonX,
      3,
      buttonBaseWidth,
      30
    )

    -- Get the actual width of the button after skin is applied
    local actualButtonWidth = setBtn:GetWidth()
    dynamicButtonsWidth = dynamicButtonsWidth + actualButtonWidth + buttonGap

    -- Set up button handlers
    setBtn.OnClick = function()
      if (api.Input:IsShiftKeyDown()) then
        table.remove(settings.gear_sets, i)
        api.SaveSettings()
        renderGearSetUI()
        return
      end

      -- Disable all buttons before starting equipment process
      disableAllGearSetButtons()
      enqueueLoadoutEquipment(gear_set)
    end
    setBtn:SetHandler("OnClick", setBtn.OnClick)

    -- Set up tooltip handlers
    local name = gear_set.name or "Unnamed Set"
    function setBtn:OnEnter()
      local PosX, PosY = self:GetOffset()
      local description = ""
      if api.Input:IsShiftKeyDown() then
        description = name .. "\nShift + Left-click to remove the loadout."
      else
        description = name .. "\nClick to equip this gear set."
      end
      api.Interface:SetTooltipOnPos(description, mainCanvas, PosX + 50, PosY + 20)
    end

    function setBtn:OnLeave()
      local PosX, PosY = self:GetOffset()

      api.Interface:SetTooltipOnPos(nil, mainCanvas, PosX + 50, PosY + 20)
    end

    setBtn:SetHandler("OnEnter", setBtn.OnEnter)
    setBtn:SetHandler("OnLeave", setBtn.OnLeave)

    table.insert(gearSetButtons, setBtn)
  end

  -- Recreate add button with unique ID
  local addButtonId = getUniqueWidgetId("addSetButton")

  local useExtraGap = numGearSets > 0 and addButtonExtraGap or 0
  -- Position add button after the last gear set button using accumulated dynamic width
  local addButtonX = leftPadding + dynamicButtonsWidth + useExtraGap

  addSetButton = ui.createButton(
    addButtonId,
    mainCanvas,
    "+",
    addButtonX,
    3,
    60,
    30
  )

  function addSetButton:OnEnter()
    local PosX, PosY = self:GetOffset()
    api.Interface:SetTooltipOnPos(
      "Set Swap\n\nClick to create a new loadout definition.\nIt will be saved based on your current equiped gear.\n\nYou can freely move this window with Shift+Left-click dragging.",
      mainCanvas, PosX + 50, PosY + 20)
  end

  function addSetButton:OnLeave()
    local PosX, PosY = self:GetOffset()
    api.Interface:SetTooltipOnPos(nil, mainCanvas, PosX + 50, PosY + 20)
  end

  addSetButton:SetHandler("OnEnter", addSetButton.OnEnter)
  addSetButton:SetHandler("OnLeave", addSetButton.OnLeave)

  -- Update canvas size based on actual button widths
  local addButtonWidth = addSetButton:GetWidth()
  local totalRequiredWidth = leftPadding + dynamicButtonsWidth + addButtonWidth + rightPadding + useExtraGap
  mainCanvas:SetExtent(totalRequiredWidth, baseCanvasHeight)

  local function saveNewSet(setNameInput)
    local setName = ""
    if setNameInput and setNameInput ~= "" then
      setName = setNameInput
    else
      setName = "New Gear Set" .. " (" .. #settings.gear_sets + 1 .. ")"
    end

    local items = {}
    local gear_pieces = { 1, 3, 4, 8, 6, 9, 5, 7, 15, 2, 10, 11, 12, 13, 16, 17, 18, 19, 28 }
    for _, i in ipairs(gear_pieces) do
      local item = api.Equipment:GetEquippedItemTooltipInfo(i)
      if item ~= nil then
        local new_item = { name = item.name, grade = item.itemGrade, slot = i }
        if i == 13 or i == 11 or i == 17 then
          new_item.alternative = true
        end
        table.insert(items, new_item)
      end
    end

    local loadout = { name = setName, gear = items }

    local loadout_exists = false
    if (settings and settings.gear_sets) then
      for i, v in ipairs(settings.gear_sets) do
        if v.name == setName then
          settings.gear_sets[i] = loadout
          loadout_exists = true
          break
        end
      end
    end

    if not loadout_exists then
      settings.gear_sets = settings.gear_sets or {}

      table.insert(settings.gear_sets, loadout)
    end

    api.SaveSettings()
    renderGearSetUI()
  end

  addSetButton.OnClick = function()
    local promptUi = ui.promptUserInput("Enter Gear Set Name", saveNewSet)
    addNewSetCanvas = promptUi.canvas
    addNewSetCanvas.textEdit = promptUi.textEdit
    addNewSetCanvas:Show(true)
  end
  addSetButton:SetHandler("OnClick", addSetButton.OnClick)

  -- Ensure buttons are enabled if no items are being processed
  if #enqueuedItems == 0 then
    enableAllGearSetButtons()
  end

  mainCanvas:Show(true)
  mainCanvas:EnableDrag(true)
end

local function OnLoad()
  settings = api.GetSettings("set_swap")
  if not settings then
    settings = {
      x = 200,
      y = 400,
      gear_sets = {}
    }
    api.SaveSettings("set_swap", settings)
  end
  settings.gear_sets = settings.gear_sets or {}
  renderGearSetUI()
end

local function OnUnload()
  if mainCanvas then
    mainCanvas:Show(false)
    mainCanvas:Destroy()
    mainCanvas = nil
  end

  if addNewSetCanvas then
    addNewSetCanvas:Show(false)
    addNewSetCanvas:Destroy()
    addNewSetCanvas = nil
  end
end

function processNextEquip()
  if #enqueuedItems == 0 then
    isProcessingEquip = false

    enableAllGearSetButtons()
    return
  end

  isProcessingEquip = true
  local equipableItem = table.remove(enqueuedItems, 1)

  equipBagItem(equipableItem.bagSlot, equipableItem.equipmentSlot)

  -- Check if item was equipped after the delay
  api:DoIn(retryDelay, function()
    local equippedItem = api.Equipment:GetEquippedItemTooltipInfo(equipableItem.equipmentSlot)
    local wasEquipped = false
    
    -- Check if the correct item is now equipped
    if equippedItem and equippedItem.name == equipableItem.item.name and equippedItem.itemGrade == equipableItem.item.itemGrade then
      wasEquipped = true
    end
    
    -- If not equipped and we haven't exceeded max retries, try again
    if not wasEquipped and equipableItem.retryCount < maxRetries then
      equipableItem.retryCount = equipableItem.retryCount + 1
      -- Re-enqueue the item at the front of the queue to retry immediately
      table.insert(enqueuedItems, 1, equipableItem)
      -- Continue processing with a shorter delay for retry
      api:DoIn(retryDelay, processNextEquip)
    else
      -- Item was equipped or max retries reached, move to next item
      api:DoIn(betweenItemDelay, processNextEquip())
    end
  end)

end

set_swap.OnUnload = OnUnload
set_swap.OnLoad = OnLoad

return set_swap
