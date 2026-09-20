#!/bin/bash
# 取一个指数/股票的最新行情，输出形如「3912 +0.94%」
#
# 用法：
#   quote.sh s_sh000001   上证指数
#   quote.sh s_sz399001   深证成指
#   quote.sh s_sz399006   创业板指
#   quote.sh gb_dji       道琼斯
#   quote.sh gb_ixic      纳斯达克
#   quote.sh gb_inx       标普500
#   quote.sh sh600519     个股（贵州茅台）
#
# 数据来自新浪财经的公开行情接口，不需要 API Key。
# 非交易时段返回最近一次收盘数据。
set -uo pipefail

code="${1:-s_sh000001}"
raw=$(curl -s --max-time 4 -H "Referer: https://finance.sina.com.cn" \
      "https://hq.sinajs.cn/list=${code}" 2>/dev/null | iconv -f GBK -t UTF-8 2>/dev/null)

# 取出引号里的内容
body=$(printf '%s' "$raw" | sed -n 's/.*="\([^"]*\)".*/\1/p')
[ -z "$body" ] && { echo "—"; exit 0; }

# A 股（s_ 前缀）:  名称,价格,涨跌额,涨跌幅
# 美股（gb_ 前缀）: 名称,价格,涨跌幅,时间,涨跌额
# 个股（无前缀）:   名称,今开,昨收,现价,...
case "$code" in
  s_*)  price=$(echo "$body" | cut -d, -f2); pct=$(echo "$body" | cut -d, -f4) ;;
  gb_*) price=$(echo "$body" | cut -d, -f2); pct=$(echo "$body" | cut -d, -f3) ;;
  *)    price=$(echo "$body" | cut -d, -f4)
        prev=$(echo "$body" | cut -d, -f3)
        pct=$(awk -v p="$price" -v c="$prev" 'BEGIN{ if (c+0==0) print 0; else printf "%.2f",(p-c)/c*100 }') ;;
esac

[ -z "$price" ] && { echo "—"; exit 0; }

# 价格取整（指数都是四位数以上，小数位没意义），涨跌幅保留两位并补正号
awk -v p="$price" -v c="$pct" 'BEGIN{
  if (p+0 == 0) { print "—"; exit }
  printf "%.0f %s%.2f%%\n", p, (c+0>=0 ? "+" : ""), c
}'
