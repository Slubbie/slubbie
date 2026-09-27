-- Evergrove server entry point.
--
-- Builds the world, then boots every service (see Services/init.luau for the
-- order). Everything gameplay-related is server-authoritative: clients only
-- send requests, which the Net router validates before any service sees them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Lib.Net) -- creates the remotes before clients look for them

local Services = require(script.Services)
Services.Boot()
