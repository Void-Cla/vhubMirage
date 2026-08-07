-- cl.lua — shim R15 (ADR #81 FASE 1)
-- A mecânica de drift foi absorvida por vhub_custom/client/drift.lua.
-- Este arquivo preserva o export getTelemetry() para consumidores legados
-- durante a transição (R15: contrato não quebra sem deprecation path).
-- Consumidores novos devem usar exports.vhub_custom:driftTelemetry() diretamente.
---@diagnostic disable: undefined-global

exports('getTelemetry', function()
  local ok, res = pcall(function() return exports.vhub_custom:driftTelemetry() end)
  return ok and res or nil
end)
