import Foundation

/// 一只要显示的标的
struct StockItem: Decodable {
    /// 面板上的标签，如「上证」
    var label: String
    /// 行情代码，如 s_sh000001 / gb_ixic / sh600519
    var code: String

    enum CodingKeys: String, CodingKey { case label, code }

    // 自定义了 init(from:) 之后，memberwise 初始化器不再自动合成，得手写
    init(label: String, code: String) {
        self.label = label
        self.code = code
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        code = try c.decode(String.self, forKey: .code)
    }
}

/// 菜单里可直接勾选的常用标的
enum StockPresets {
    static let all: [(label: String, code: String)] = [
        ("上证指数", "s_sh000001"),
        ("深证成指", "s_sz399001"),
        ("创业板指", "s_sz399006"),
        ("沪深300", "s_sh000300"),
        ("恒生指数", "int_hangseng"),
        ("道琼斯", "gb_dji"),
        ("纳斯达克", "gb_ixic"),
        ("标普500", "gb_inx"),
    ]
    static func label(for code: String) -> String? {
        all.first { $0.code == code }?.label
    }
}

/// 股票/指数配置
struct StockConfig: Decodable {
    /// 多少秒刷新一次，最小 10 秒
    var interval: Double = 60
    var items: [StockItem] = []

    enum CodingKeys: String, CodingKey { case interval, items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? 60
        items = try c.decodeIfPresent([StockItem].self, forKey: .items) ?? []
    }
}

/// 行情采集。内置而非调用外部脚本，好处是：
/// - 装到哪儿都能用，不依赖脚本路径
/// - 多个代码合并成一次请求，而不是每只标的 fork 一个 curl
///
/// 数据来自新浪财经的公开行情接口，不需要 API Key。非交易时段返回最近收盘数据。
final class StockProvider: @unchecked Sendable {
    private var cache: [String: String] = [:]
    private var lastFetch: Date?
    private var lastCodes = ""

    func fetch(_ cfg: StockConfig) -> [String: String] {
        guard !cfg.items.isEmpty else { return [:] }
        let codes = cfg.items.map(\.code).joined(separator: ",")

        // 标的列表变了就立刻重取，不等冷却——否则在菜单里加一只股票，
        // 要干等一个刷新周期才看得见。
        if codes != lastCodes {
            lastCodes = codes
            lastFetch = nil
            cache = [:]
        }

        let interval = max(cfg.interval, 10)
        if let last = lastFetch, Date().timeIntervalSince(last) < interval { return cache }
        lastFetch = Date()
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(codes)") else { return cache }
        var req = URLRequest(url: url)
        // 这个接口校验来源，不带 Referer 会被拒
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 6

        guard let data = send(req),
              // 返回体是 GBK。这里只取数字和逗号，中文名称用不上（标签由配置给），
              // 所以用 latin1 按字节解码就够，省掉一次编码转换。
              let text = String(data: data, encoding: .isoLatin1)
        else { return cache }

        var out: [String: String] = [:]
        for item in cfg.items {
            if let v = parse(text, code: item.code) { out[item.label] = v }
        }
        if !out.isEmpty { cache = out }
        return cache
    }

    /// 从整段响应里取出某个代码那一行并格式化成「3912 +0.94%」
    private func parse(_ text: String, code: String) -> String? {
        guard let lineRange = text.range(of: "hq_str_\(code)=\"") else { return nil }
        let rest = text[lineRange.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let fields = rest[..<end].components(separatedBy: ",")
        guard fields.count > 3 else { return nil }

        let price: Double?
        let pct: Double?
        if code.hasPrefix("s_") {
            // A 股指数：名称,现价,涨跌额,涨跌幅
            price = Double(fields[1]); pct = Double(fields[3])
        } else if code.hasPrefix("int_") {
            // 国际指数：名称,现价,涨跌额,涨跌幅
            price = Double(fields[1]); pct = Double(fields[3])
        } else if code.hasPrefix("gb_") {
            // 美股：名称,现价,涨跌幅,时间,涨跌额
            price = Double(fields[1]); pct = Double(fields[2])
        } else {
            // 个股：名称,今开,昨收,现价,...
            price = Double(fields[3])
            let prev = Double(fields[2]) ?? 0
            pct = (prev > 0 && fields.count > 3)
                ? ((Double(fields[3]) ?? 0) - prev) / prev * 100 : nil
        }
        guard let p = price, p > 0, let c = pct else { return nil }
        return String(format: "%.0f %@%.2f%%", p, c >= 0 ? "+" : "", c)
    }

    /// 查一个代码对应的中文名称，用于「添加代码」时自动填标签。
    /// 这里要正确按 GBK 解码——名称是要显示给人看的，不能像取数字那样凑合。
    func lookupName(_ code: String) -> String? {
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(code)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 6
        guard let data = send(req) else { return nil }
        let gbk = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        guard let text = String(data: data, encoding: String.Encoding(rawValue: gbk)),
              let r = text.range(of: "hq_str_\(code)=\""),
              let end = text[r.upperBound...].firstIndex(of: "\"")
        else { return nil }
        let body = text[r.upperBound..<end]
        guard !body.isEmpty else { return nil }
        var name = body.components(separatedBy: ",").first ?? ""
        // 港股那类返回「HSI,恒生指数,...」，第一段是英文代码
        if name.range(of: "^[A-Za-z0-9.]+$", options: .regularExpression) != nil,
           body.components(separatedBy: ",").count > 1 {
            name = body.components(separatedBy: ",")[1]
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(6))
    }

    private func send(_ req: URLRequest) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            result = data
        }.resume()
        _ = sem.wait(timeout: .now() + 8)
        return result
    }
}
