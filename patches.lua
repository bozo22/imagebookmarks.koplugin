local _ = require("gettext")
local ImageViewer = require("ui/widget/imageviewer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local FileManagerUtil = require("apps/filemanager/filemanagerutil")
local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local ImageViewer_init = ImageViewer.init
local DocSettings_updateLocation = DocSettings.updateLocation

local Patches = {}

function Patches.add_bookmark_button(iv)
    if not (iv.button_table and iv.button_table.buttons and iv.button_table.buttons[1]) then
        return
    end
    local row = iv.button_table.buttons[1]
    for _, btn in ipairs(row) do
        if btn.id == "imagebookmark" then return end
    end

    local insert_pos = #row -- before last
    table.insert(row, insert_pos, {
        id = "imagebookmark",
        text = _("Bookmark"),
        callback = function()
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("ImageBookmarkAdd", iv.image))
        end,
    })

    -- Rebuild the ButtonTable / container similar to original pattern
    iv.button_table = ButtonTable:new {
        width = iv.width - 2 * iv.button_padding,
        buttons = iv.button_table.buttons,
        zero_sep = true,
        show_parent = iv,
    }
    iv.button_container = CenterContainer:new {
        dimen = Geom:new {
            w = iv.width,
            h = iv.button_table:getSize().h,
        },
        iv.button_table,
    }
end

function Patches.ImageViewer_patch()
    ImageViewer.init = function(self, ...)
        ImageViewer_init(self, ...)
        -- safe add button after the viewer finishes init
        pcall(Patches.add_bookmark_button, self)
    end
end

function Patches.ImageViewer_undo_patch()
    ImageViewer.init = ImageViewer_init
end

function Patches.DocSettings_patch()
    DocSettings.updateLocation = function(doc_path, new_doc_path, copy)
        DocSettings_updateLocation(doc_path, new_doc_path, copy)
        -- broadcast the event (safe)
        pcall(function()
            UIManager:broadcastEvent(Event:new("LocationUpdated", doc_path, new_doc_path, copy))
        end)
    end
end

function Patches.FileManagerUtil_patch()
    FileManagerUtil.genResetSettingsButton = function(doc_settings_or_file, caller_callback, button_disabled)
        local doc_settings, file, has_sidecar_file
        if type(doc_settings_or_file) == "table" then
            doc_settings = doc_settings_or_file
            file = doc_settings_or_file:readSetting("doc_path")
            has_sidecar_file = true
        else
            file = ffiUtil.realpath(doc_settings_or_file) or doc_settings_or_file
            has_sidecar_file = BookList.hasBookBeenOpened(file)
        end
        local custom_cover_file = DocSettings:findCustomCoverFile(file)
        local has_custom_cover_file = custom_cover_file and true or false
        local custom_metadata_file = DocSettings:findCustomMetadataFile(file)
        local has_custom_metadata_file = custom_metadata_file and true or false
        return {
            text = _("Reset"),
            enabled = not button_disabled and (has_sidecar_file or has_custom_metadata_file or has_custom_cover_file),
            callback = function()
                local check_button_settings, check_button_cover, check_button_metadata
                local confirmbox = ConfirmBox:new {
                    text = T(_("Reset this document?") .. "\n\n%1\n\n" ..
                        _("Information will be permanently lost."),
                        BD.filepath(file)),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        local data_to_purge = {
                            doc_settings         = check_button_settings.checked,
                            custom_cover_file    = check_button_cover.checked and custom_cover_file,
                            custom_metadata_file = check_button_metadata.checked and custom_metadata_file,
                        }
                        (doc_settings or DocSettings:open(file)):purge(nil, data_to_purge)
                        UIManager:broadcastEvent(Event:new("LocationUpdated", file))
                        if data_to_purge.custom_cover_file or data_to_purge.custom_metadata_file then
                            UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                        end
                        if data_to_purge.doc_settings then
                            BookList.setBookInfoCacheProperty(file, "been_opened", false)
                            require("readhistory"):fileSettingsPurged(file)
                        end
                        caller_callback()
                    end,
                }
                check_button_settings = CheckButton:new {
                    text = _("document settings, progress, bookmarks, highlights, notes"),
                    checked = has_sidecar_file,
                    enabled = has_sidecar_file,
                    parent = confirmbox,
                }
                confirmbox:addWidget(check_button_settings)
                check_button_cover = CheckButton:new {
                    text = _("custom cover image"),
                    checked = has_custom_cover_file,
                    enabled = has_custom_cover_file,
                    parent = confirmbox,
                }
                confirmbox:addWidget(check_button_cover)
                check_button_metadata = CheckButton:new {
                    text = _("custom book metadata"),
                    checked = has_custom_metadata_file,
                    enabled = has_custom_metadata_file,
                    parent = confirmbox,
                }
                confirmbox:addWidget(check_button_metadata)
                UIManager:show(confirmbox)
            end,
        }
    end
end

pcall(Patches.DocSettings_patch)
pcall(Patches.FileManagerUtil_patch)

return Patches
