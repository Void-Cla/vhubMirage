function AddEntity(entity, options)
    if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(entity, options)
    elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
        local qbOptions = {}
        local distance = 2.0
        
        for _, opt in ipairs(options) do
            if opt.distance then distance = opt.distance end
            table.insert(qbOptions, {
                type = "client",
                action = opt.onSelect,
                icon = opt.icon,
                label = opt.label,
            })
        end
        
        exports['qb-target']:AddTargetEntity(entity, {
            options = qbOptions,
            distance = distance
        })
    end
end