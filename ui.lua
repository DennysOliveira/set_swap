local api = require('api')

local function createButton(id, parent, text, x, y, width, height, anchor)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor(anchor or "TOPLEFT", x, y)
    button:SetText(text)

    local skin = BUTTON_BASIC.DEFAULT
    skin.width = width or 80
    skin.height = height or 30

    api.Interface:ApplyButtonSkin(button, skin)

    button:Show(true)

    return button
end

-- Creates a window for the user to input a text data and returns the input content
local function createPopupUserTextInputScreen(question, callback)
    local popup = api.Interface:CreateEmptyWindow("setSwapPopup", "UIParent")
    popup:AddAnchor("CENTER", "UIParent", 0, 0)
    popup:SetExtent(300, 180)

    popup.background = popup:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    popup.background:SetTextureInfo("bg_quest")
    popup.background:SetColor(0, 0, 0, 0.8)
    popup.background:AddAnchor("TOPLEFT", popup, 0, 0)
    popup.background:AddAnchor("BOTTOMRIGHT", popup, 0, 0)


    local label = popup:CreateChildWidget("label", "setSwapLabel", 10, true)
    label:SetText(question or "Please enter your input:")
    label.style:SetFontSize(14)
    label:SetExtent(240, 25)
    label:AddAnchor("TOP", popup, 0, 20) -- Centered horizontally


    local textEdit = W_CTRL.CreateEdit("textEdit_" .. tostring(math.random(1000)), popup)
    textEdit:SetExtent(240, 30)
    textEdit:AddAnchor("TOP", label, "BOTTOM", 0, 2)


    local confirmButton = createButton(
        "confirmButton",
        popup,
        "Confirm",
        0,
        -40,
        100,
        30,
        "BOTTOM"
    )


    textEdit.OnTextChanged = function()
        local text = textEdit:GetText()
    end
    textEdit:SetHandler("OnTextChanged", textEdit.OnTextChanged)


    confirmButton.OnClick = function()
        local inputText = textEdit:GetText()

        if inputText and inputText ~= "" then
            popup:Show(false)
            callback(inputText)
        else
            api.Log:Warning("No valid input provided.")
        end
    end
    confirmButton:SetHandler("OnClick", confirmButton.OnClick)

    popup:EnableDrag(true)

    function popup:OnDragStart()
        popup:StartMoving()
        api.Cursor:ClearCursor()
        api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end

    popup:SetHandler("OnDragStart", popup.OnDragStart)

    function popup:OnDragStop()
        popup:StopMovingOrSizing()
        api.Cursor:ClearCursor()
    end

    popup:SetHandler("OnDragStop", popup.OnDragStop)

    return {
        canvas = popup,
        textEdit = textEdit,
    }
end

local ui = {
    createButton = createButton,
    promptUserInput = createPopupUserTextInputScreen,
}

return ui
