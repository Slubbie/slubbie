-- Monetization: fair and mostly cosmetic.
--
-- Nothing here sells crops, currency, growth speed, mutation chances or
-- competitive advantages. All crops, regions, animals and progression are
-- earned by playing. Game passes and developer products are set up in the
-- Creator Dashboard; put their ids here (0 = not configured → hidden in the store).
--
-- Kinds
--   Pass     one-time game pass (GamePassId)
--   Product  developer product (ProductId); repeatable purchases are recorded by
--            PurchaseId so a receipt is never granted twice
--
-- Grants: Cosmetic (list of cosmetic ids), LayoutSlots, Title, Theme, MusicPack,
--         Companion, Nameplate, Emotes, Mail (extra gift box), Supporter

return {
	Items = {
		{
			Id = "theme_cottage",
			Name = "Cottagecore Farm Theme",
			Icon = "🏡",
			Kind = "Pass",
			GamePassId = 0,
			Price = 199,
			Grants = { Cosmetic = { "farmhouse_cottage", "fence_cottage", "ui_cottage" } },
			Description = "A storybook farmhouse skin, fence set and UI theme.",
		},
		{
			Id = "theme_celestial",
			Name = "Celestial Farm Theme",
			Icon = "🌌",
			Kind = "Pass",
			GamePassId = 0,
			Price = 299,
			Grants = { Cosmetic = { "farmhouse_celestial", "ui_celestial", "path_stars" } },
			Description = "A starlit farmhouse skin, glowing paths and a night-sky UI.",
		},
		{
			Id = "ui_themes",
			Name = "UI Theme Pack",
			Icon = "🎨",
			Kind = "Pass",
			GamePassId = 0,
			Price = 99,
			Grants = { Cosmetic = { "ui_parchment", "ui_midnight", "ui_sakura" } },
			Description = "Three extra interface themes.",
		},
		{
			Id = "companion_fox",
			Name = "Fox Companion",
			Icon = "🦊",
			Kind = "Pass",
			GamePassId = 0,
			Price = 149,
			Grants = { Companion = "fox" },
			Description = "A cosmetic fox that follows you around. It does nothing useful. It's perfect.",
		},
		{
			Id = "companion_owl",
			Name = "Owl Companion",
			Icon = "🦉",
			Kind = "Pass",
			GamePassId = 0,
			Price = 149,
			Grants = { Companion = "owl" },
			Description = "A sleepy owl that perches on your shoulder at night.",
		},
		{
			Id = "music_pack",
			Name = "Seasonal Music Pack",
			Icon = "🎵",
			Kind = "Pass",
			GamePassId = 0,
			Price = 99,
			Grants = { MusicPack = "folk" },
			Description = "A folk arrangement of every seasonal theme.",
		},
		{
			Id = "emote_pack",
			Name = "Farmer's Emote Pack",
			Icon = "💃",
			Kind = "Pass",
			GamePassId = 0,
			Price = 99,
			Grants = { Emotes = { "HarvestDance", "Yodel", "TipHat", "Scarecrow" } },
			Description = "Four emotes for photo mode and festivals.",
		},
		{
			Id = "nameplates",
			Name = "Nameplate Styles",
			Icon = "🏷️",
			Kind = "Pass",
			GamePassId = 0,
			Price = 79,
			Grants = { Nameplate = { "vine", "golden", "sakura" } },
			Description = "Three decorative nameplate styles.",
		},
		{
			Id = "layouts",
			Name = "Extra Layout Slots",
			Icon = "📐",
			Kind = "Pass",
			GamePassId = 0,
			Price = 149,
			Grants = { LayoutSlots = 6 },
			Description = "Save 6 more farm decoration layouts.",
		},
		{
			Id = "tool_skins",
			Name = "Heirloom Tool Skins",
			Icon = "✨",
			Kind = "Pass",
			GamePassId = 0,
			Price = 199,
			Grants = { Cosmetic = { "tools_heirloom" } },
			Description = "Engraved wooden-and-brass looks for every tool (visual only).",
		},
		{
			Id = "supporter",
			Name = "Supporter",
			Icon = "💚",
			Kind = "Pass",
			GamePassId = 0,
			Price = 249,
			Grants = { Title = "Supporter", Nameplate = { "supporter" }, Supporter = true },
			Description = "Thank you! A supporter title and nameplate, plus a thank-you letter.",
		},
		{
			Id = "gift_box",
			Name = "Gift a Festival Box",
			Icon = "🎁",
			Kind = "Product",
			ProductId = 0,
			Price = 25,
			Grants = { GiftCosmeticBox = true },
			Description = "Send a friend a box of seasonal decorations.",
		},
	},
	-- Cosmetic catalog (id → display). Owned cosmetics are stored in the profile.
	Cosmetics = {
		farmhouse_cottage = { Name = "Cottage Farmhouse", Slot = "House" },
		farmhouse_celestial = { Name = "Celestial Farmhouse", Slot = "House" },
		fence_cottage = { Name = "Cottage Fences", Slot = "Fence" },
		path_stars = { Name = "Starlit Paths", Slot = "Path" },
		ui_cottage = { Name = "Cottage UI", Slot = "UI" },
		ui_celestial = { Name = "Celestial UI", Slot = "UI" },
		ui_parchment = { Name = "Parchment UI", Slot = "UI" },
		ui_midnight = { Name = "Midnight UI", Slot = "UI" },
		ui_sakura = { Name = "Sakura UI", Slot = "UI" },
		tools_heirloom = { Name = "Heirloom Tools", Slot = "Tools" },
	},
	BaseLayoutSlots = 3,
}
