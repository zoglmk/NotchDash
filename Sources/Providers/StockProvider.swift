import Foundation

/// 一只要显示的标的
struct StockItem: Decodable {
    /// 面板上的标签，如「上证」
    var label: String
    /// 行情代码，如 s_sh000001 / gb_ixic / sh600519
    var code: String

    enum CodingKeys: String, CodingKey { case label, code }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        code = try c.decode(String.self, forKey: .code)
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

    func fetch(_ cfg: StockConfig) -> [String: String] {
        guard !cfg.items.isEmpty else { return [:] }
        let interval = max(cfg.interval, 10)
        if let last = lastFetch, Date().timeIntervalSince(last) < interval { return cache }
        lastFetch = Date()

        let codes = cfg.items.map(\.code).joined(separator: ",")
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
