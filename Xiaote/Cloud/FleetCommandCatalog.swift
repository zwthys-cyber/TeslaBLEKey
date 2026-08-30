import Foundation

struct FleetCommandDefinition: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case access = "门锁与车身"
        case charging = "充电"
        case climate = "座舱与空调"
        case media = "媒体"
        case navigation = "导航"
        case security = "安全与驾驶"
        case scheduling = "预约"
        case maintenance = "车辆与维护"
        var id: String { rawValue }
    }

    enum Risk: Int, Sendable { case normal, confirmation, critical }

    let id: String
    let title: String
    let summary: String
    let category: Category
    let symbol: String
    let risk: Risk
    let payloadTemplate: String

    init(_ id: String, _ title: String, _ summary: String, _ category: Category,
         _ symbol: String, risk: Risk = .confirmation, payload: String = "{}") {
        self.id = id; self.title = title; self.summary = summary; self.category = category
        self.symbol = symbol; self.risk = risk; self.payloadTemplate = payload
    }

    static let all: [Self] = [
        .init("door_lock", "锁定车辆", "锁定所有车门", .access, "lock.fill"),
        .init("door_unlock", "解锁车辆", "解锁所有车门", .access, "lock.open.fill", risk: .critical),
        .init("actuate_trunk", "控制行李厢", "打开前备箱或操作电动尾门", .access, "car.rear.road.lane", payload: #"{"which_trunk":"rear"}"#),
        .init("window_control", "控制车窗", "通风或关闭全部车窗", .access, "rectangle.split.3x1", payload: #"{"command":"close","lat":0,"lon":0}"#),
        .init("sun_roof_control", "控制天窗", "控制支持车型的天窗", .access, "sunroof.open", payload: #"{"state":"close"}"#),
        .init("flash_lights", "闪灯", "闪烁车辆外部灯光", .access, "light.beacon.max.fill", risk: .normal),
        .init("honk_horn", "鸣笛", "鸣响车辆喇叭", .access, "speaker.wave.3.fill", risk: .normal),
        .init("trigger_homelink", "触发 HomeLink", "在车辆当前位置触发已配置的车库门", .access, "house.fill", payload: #"{"lat":0,"lon":0}"#),

        .init("charge_start", "开始充电", "开始已连接的充电会话", .charging, "bolt.fill"),
        .init("charge_stop", "停止充电", "停止当前充电会话", .charging, "stop.fill"),
        .init("charge_port_door_open", "打开充电口", "打开车辆充电口盖", .charging, "bolt.car.fill"),
        .init("charge_port_door_close", "关闭充电口", "关闭车辆充电口盖", .charging, "bolt.car"),
        .init("set_charge_limit", "设置充电上限", "设置目标电量百分比", .charging, "battery.75percent", payload: #"{"percent":80}"#),
        .init("set_charging_amps", "设置充电电流", "设置交流充电电流", .charging, "gauge.with.dots.needle.33percent", payload: #"{"charging_amps":16}"#),
        .init("charge_max_range", "充满", "临时将充电上限设为最高", .charging, "battery.100percent"),
        .init("charge_standard", "标准充电上限", "恢复车辆默认标准充电上限", .charging, "battery.75percent"),

        .init("auto_conditioning_start", "开启空调", "启动座舱温度调节", .climate, "fan.fill"),
        .init("auto_conditioning_stop", "关闭空调", "停止座舱温度调节", .climate, "fan.slash.fill"),
        .init("set_temps", "设置温度", "设置主副驾驶目标温度", .climate, "thermometer.medium", payload: #"{"driver_temp":22,"passenger_temp":22}"#),
        .init("set_preconditioning_max", "最大除霜", "开启或关闭最大除霜", .climate, "windshield.front.and.heat.waves", payload: #"{"on":true}"#),
        .init("set_climate_keeper_mode", "保持空调模式", "设置保持、爱犬、露营或关闭", .climate, "pawprint.fill", payload: #"{"climate_keeper_mode":0}"#),
        .init("set_bioweapon_mode", "生化防御模式", "开启或关闭生化防御", .climate, "aqi.high", payload: #"{"on":true,"manual_override":true}"#),
        .init("set_cabin_overheat_protection", "座舱过热保护", "开启或关闭座舱过热保护", .climate, "thermometer.sun.fill", payload: #"{"on":true,"fan_only":false}"#),
        .init("set_cop_temp", "过热保护温度", "设置座舱过热保护阈值", .climate, "thermometer.high", payload: #"{"cop_temp":"High"}"#),
        .init("remote_seat_heater_request", "座椅加热", "设置指定座椅加热等级", .climate, "carseat.left.and.heat.waves.fill", payload: #"{"heater":0,"level":1}"#),
        .init("remote_seat_cooler_request", "座椅通风", "设置指定座椅通风等级", .climate, "carseat.left.fan.fill", payload: #"{"seat_position":0,"seat_cooler_level":1}"#),
        .init("remote_auto_seat_climate_request", "自动座椅温控", "设置指定座椅自动温控", .climate, "carseat.left.fill", payload: #"{"auto_seat_position":0,"auto_climate_on":true}"#),
        .init("remote_steering_wheel_heater_request", "方向盘加热", "开启或关闭方向盘加热", .climate, "steeringwheel.and.heat.waves", payload: #"{"on":true}"#),
        .init("remote_steering_wheel_heat_level_request", "方向盘加热等级", "设置方向盘加热等级", .climate, "steeringwheel", payload: #"{"level":1}"#),
        .init("remote_auto_steering_wheel_heat_climate_request", "自动方向盘加热", "设置方向盘自动加热", .climate, "steeringwheel", payload: #"{"on":true}"#),

        .init("media_toggle_playback", "播放或暂停", "切换车载媒体播放状态", .media, "playpause.fill", risk: .normal),
        .init("media_next_track", "下一首", "切换到下一首曲目", .media, "forward.end.fill", risk: .normal),
        .init("media_prev_track", "上一首", "切换到上一首曲目", .media, "backward.end.fill", risk: .normal),
        .init("media_next_fav", "下一个收藏", "切换至下一个收藏内容", .media, "star.fill", risk: .normal),
        .init("media_prev_fav", "上一个收藏", "切换至上一个收藏内容", .media, "star", risk: .normal),
        .init("media_volume_up", "提高音量", "逐级提高车载媒体音量", .media, "speaker.plus.fill", risk: .normal),
        .init("media_volume_down", "降低音量", "逐级降低车载媒体音量", .media, "speaker.minus.fill", risk: .normal),
        .init("adjust_volume", "设置音量", "精确设置车载媒体音量", .media, "speaker.wave.2.fill", payload: #"{"volume":5}"#),
        .init("remote_boombox", "外放音效", "在支持车型上播放外部音效", .media, "hifispeaker.fill", payload: #"{"sound":0}"#),

        .init("navigation_request", "发送目的地", "向车辆导航发送地址", .navigation, "map.fill", payload: #"{"type":"share_ext_content_raw","locale":"zh-CN","timestamp_ms":"0","value":{"android.intent.extra.TEXT":"目的地"}}"#),
        .init("navigation_gps_request", "发送坐标", "向车辆导航发送经纬度", .navigation, "location.fill", payload: #"{"lat":0,"lon":0,"order":0}"#),
        .init("navigation_sc_request", "导航至超级充电站", "向车辆发送超级充电站导航", .navigation, "bolt.car.fill", payload: #"{"id":0,"order":0}"#),
        .init("navigation_waypoints_request", "发送途经点", "向车辆发送多点路线", .navigation, "point.topleft.down.to.point.bottomright.curvepath", payload: #"{"waypoints":[]}"#),
        .init("upcoming_calendar_entries", "同步日历行程", "向车辆发送即将到来的日历条目", .navigation, "calendar", payload: #"{"calendar_data":[]}"#),

        .init("set_sentry_mode", "哨兵模式", "开启或关闭哨兵模式", .security, "eye.fill", payload: #"{"on":true}"#),
        .init("remote_start_drive", "远程驾驶授权", "在短时间内允许无钥匙驾驶", .security, "power", risk: .critical),
        .init("set_pin_to_drive", "PIN 驾驶", "开启、关闭或修改 PIN 驾驶", .security, "rectangle.and.pencil.and.ellipsis", risk: .critical, payload: #"{"on":true,"password":""}"#),
        .init("reset_pin_to_drive_pin", "重置 PIN 驾驶", "重置 PIN 驾驶密码", .security, "arrow.counterclockwise", risk: .critical),
        .init("clear_pin_to_drive_admin", "管理员清除 PIN 驾驶", "通过管理员授权清除 PIN", .security, "person.badge.key.fill", risk: .critical),
        .init("set_valet_mode", "代客模式", "开启或关闭代客模式", .security, "person.crop.circle.badge.key.fill", risk: .critical, payload: #"{"on":true,"password":""}"#),
        .init("reset_valet_pin", "重置代客 PIN", "重置代客模式密码", .security, "arrow.counterclockwise", risk: .critical),
        .init("guest_mode", "访客模式", "开启或关闭车辆访客模式", .security, "person.crop.circle.badge.checkmark", risk: .critical, payload: #"{"enable":true}"#),
        .init("speed_limit_set_limit", "设置限速", "设置车辆最高速度", .security, "gauge.with.dots.needle.67percent", risk: .critical, payload: #"{"limit_mph":55}"#),
        .init("speed_limit_activate", "启用限速", "使用 PIN 启用限速模式", .security, "gauge.with.needle.fill", risk: .critical, payload: #"{"pin":""}"#),
        .init("speed_limit_deactivate", "停用限速", "使用 PIN 停用限速模式", .security, "gauge.with.needle", risk: .critical, payload: #"{"pin":""}"#),
        .init("speed_limit_clear_pin", "清除限速 PIN", "清除限速模式 PIN", .security, "key.slash.fill", risk: .critical, payload: #"{"pin":""}"#),
        .init("speed_limit_clear_pin_admin", "管理员清除限速 PIN", "通过管理员授权清除限速 PIN", .security, "person.badge.key.fill", risk: .critical),
        .init("parental_controls_activate", "启用家长控制", "使用 PIN 启用家长控制", .security, "figure.and.child.holdinghands", risk: .critical, payload: #"{"pin":""}"#),
        .init("parental_controls_deactivate", "停用家长控制", "使用 PIN 停用家长控制", .security, "figure.and.child.holdinghands", risk: .critical, payload: #"{"pin":""}"#),
        .init("parental_controls_set_speed_limit", "家长控制限速", "设置家长控制最高速度", .security, "speedometer", risk: .critical, payload: #"{"speed_limit_mph":55}"#),
        .init("parental_controls_enable_setting", "家长控制设置", "启用或关闭一项家长控制限制", .security, "checklist", risk: .critical, payload: #"{"setting":"RequireSafetyFeatures","enable":true}"#),
        .init("parental_controls_clear_pin_admin", "管理员清除家长 PIN", "通过管理员授权清除家长控制 PIN", .security, "person.badge.key.fill", risk: .critical),

        .init("add_charge_schedule", "添加充电预约", "创建一条充电预约", .scheduling, "calendar.badge.plus", payload: #"{"lat":0,"lon":0,"start_time":0,"end_time":0,"days_of_week":127,"enabled":true}"#),
        .init("remove_charge_schedule", "删除充电预约", "按 ID 删除充电预约", .scheduling, "calendar.badge.minus", risk: .critical, payload: #"{"id":0}"#),
        .init("add_precondition_schedule", "添加预热预约", "创建一条座舱预热预约", .scheduling, "calendar.badge.plus", payload: #"{"lat":0,"lon":0,"precondition_time":0,"days_of_week":127,"enabled":true}"#),
        .init("remove_precondition_schedule", "删除预热预约", "按 ID 删除预热预约", .scheduling, "calendar.badge.minus", risk: .critical, payload: #"{"id":0}"#),
        .init("set_scheduled_charging", "旧版预约充电", "设置兼容车型的预约充电时间", .scheduling, "clock.badge", payload: #"{"enable":true,"time":0}"#),
        .init("set_scheduled_departure", "旧版预约出发", "设置兼容车型的预约出发参数", .scheduling, "clock.arrow.circlepath", payload: #"{"enable":true,"departure_time":420,"preconditioning_enabled":true,"preconditioning_weekdays_only":false,"off_peak_charging_enabled":false,"off_peak_charging_weekdays_only":false,"end_off_peak_time":0}"#),

        .init("set_vehicle_name", "车辆名称", "修改车辆显示名称", .maintenance, "pencil", payload: #"{"vehicle_name":"My Tesla"}"#),
        .init("schedule_software_update", "安排软件更新", "按延迟秒数开始软件更新", .maintenance, "arrow.down.app.fill", risk: .critical, payload: #"{"offset_sec":0}"#),
        .init("cancel_software_update", "取消软件更新", "取消已安排的软件更新", .maintenance, "xmark.circle.fill", risk: .critical),
        .init("erase_user_data", "清除车辆用户数据", "清除车辆内的个人资料和用户数据", .maintenance, "trash.fill", risk: .critical)
    ]
}

struct FleetDocumentationReference: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case guide = "官方说明", security = "密钥与安全", internalAnchor = "页面技术锚点" }
    let id: String
    let title: String
    let summary: String
    let kind: Kind
    let fragment: String

    var url: URL? {
        URL(string: "https://developer.tesla.cn/docs/fleet-api/endpoints/vehicle-commands#\(fragment)")
    }

    static let all: [Self] = [
        .init(id: "endpoints", title: "车辆命令端点", summary: "Tesla Fleet API 车辆命令总览。", kind: .guide, fragment: "endpoints"),
        .init(id: "generating_a_fleet_key", title: "生成 Fleet Key", summary: "官方 Fleet Key 生成、保管与部署说明。私钥不得进入客户端。", kind: .security, fragment: "generating-a-fleet-key"),
        .init(id: "key_pairing", title: "车辆密钥配对", summary: "将虚拟密钥与车辆安全配对的官方流程。", kind: .security, fragment: "key-pairing"),
        .init(id: "gatsby_announcer", title: "Gatsby Announcer", summary: "官方文档站用于无障碍页面导航播报的内部锚点，不是 API。", kind: .internalAnchor, fragment: "gatsby-announcer"),
        .init(id: "gatsby_chunk_mapping", title: "Gatsby Chunk Mapping", summary: "官方文档站前端资源映射锚点，不是 API。", kind: .internalAnchor, fragment: "gatsby-chunk-mapping"),
        .init(id: "gatsby_focus_wrapper", title: "Gatsby Focus Wrapper", summary: "官方文档站焦点管理锚点，不是 API。", kind: .internalAnchor, fragment: "gatsby-focus-wrapper"),
        .init(id: "gatsby_script_loader", title: "Gatsby Script Loader", summary: "官方文档站脚本加载锚点，不是 API。", kind: .internalAnchor, fragment: "gatsby-script-loader"),
        .init(id: "tds_css", title: "Tesla Design System CSS", summary: "官方文档站设计系统样式锚点，不是 API。", kind: .internalAnchor, fragment: "tds-css"),
        .init(id: "tds_site_header", title: "Tesla Design System Header", summary: "官方文档站页眉组件锚点，不是 API。", kind: .internalAnchor, fragment: "tds-site-header"),
        .init(id: "top_of_page", title: "页面顶部", summary: "官方文档页面顶部导航锚点，不是 API。", kind: .internalAnchor, fragment: "top-of-page")
    ]
}
