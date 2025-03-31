//+------------------------------------------------------------------+
//|                        All In One MA Cross.mq5                   |
//|                        Copyright 2024, Leslie                    |
//|                        https://LotusQuant.com                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, LotusQuant"
#property link "https://LotusQuant.com"
#property version "1.00"
#include <Trade/Trade.mqh>

class CTradeEx : public CTrade
{
private:
   string m_comment;  
public:
   CTradeEx() : CTrade() { m_comment = ""; }
   
   void SetComment(string comment) { m_comment = comment; }
   
   bool PositionClose(const ulong ticket, const ulong deviation = ULONG_MAX)
   {
      //--- check stopped
      if(IsStopped(__FUNCTION__))
         return(false);
      //--- check position existence
      if(!PositionSelectByTicket(ticket))
         return(false);
      string symbol = PositionGetString(POSITION_SYMBOL);
      //--- clean
      ClearStructures();
      //--- check filling
      if(!FillingCheck(symbol))
         return(false);
      //--- check
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         //--- prepare request for close BUY position
         m_request.type = ORDER_TYPE_SELL;
         m_request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         //--- prepare request for close SELL position
         m_request.type = ORDER_TYPE_BUY;
         m_request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      }
      //--- setting request
      m_request.action = TRADE_ACTION_DEAL;
      m_request.position = ticket;
      m_request.symbol = symbol;
      m_request.volume = PositionGetDouble(POSITION_VOLUME);
      m_request.magic = m_magic;
      m_request.deviation = (deviation == ULONG_MAX) ? m_deviation : deviation;
      
      // Thêm comment vào request
      m_request.comment = m_comment;
      
      //--- close position
      return(OrderSend(m_request, m_result));
   }
};
CTradeEx trade;
//+------------------------------------------------------------------+

input int CCI_Period = 14;     // CCI Period
input int OBV_SMA_Period = 20; // OBV SMA Period
input int AD_SMA_Period = 20;  // A/D SMA Period
input double CciBuy = 100;     // CCI Buy level
input double CciSell = -100;   // CCI Sell level
input ENUM_TIMEFRAMES SelectedTimeframe = PERIOD_M15;
input int MagicNumber = 123456;                       // Magic Number
input double riskMoney = 1000;                        // Risk Money
input ENUM_APPLIED_PRICE CCI_ApplyTo = PRICE_TYPICAL; // CCI Apply To
input int NumbberOfBars = 10;                         // Number of bars to calculate dynamic stop loss
input double maxLot = 0;                              // Max Lot Size user can trade
// Define the OrderEntryMode enumeration
enum OrderEntryMode
{
   ENTRY_ATO,              // At the open
   ENTRY_ATC,              // At the close
   ENTRY_LIMIT_PREV_CLOSE, // Limit at previous close
   ENTRY_LIMIT_PREV_OPEN   // Limit at previous open
};

input OrderEntryMode OrderEntryOption = ENTRY_ATO; // Choose entry mode
input bool AcceptBuy = true;                       // Enable Buy Orders
input bool AcceptSell = false;                     // Enable Sell Orders// Define the OrderEntryMode enumeration

int cci_handle;
int obv_handle;
int ad_handle;
int obv_sma_handle;
int ad_sma_handle;
double LotSize = 0.0;
double cci_buffer[];
double obv_buffer[];
double ad_buffer[];
double obv_sma_buffer[];
double ad_sma_buffer[];
double maxLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
ulong trade_ticket = 0;
datetime lastBarTime = iTime(_Symbol, SelectedTimeframe, 0);
struct TradingSignals
{
   bool buy;
   bool sell;
   bool closeBuy;
   bool closeSell;
};
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   cci_handle = iCCI(_Symbol, SelectedTimeframe, CCI_Period, CCI_ApplyTo);

   obv_handle = iOBV(_Symbol, SelectedTimeframe, VOLUME_TICK);
   ad_handle = iAD(_Symbol, SelectedTimeframe, VOLUME_TICK);

   obv_sma_handle = iMA(_Symbol, SelectedTimeframe, OBV_SMA_Period, 0, MODE_SMA, obv_handle);
   ad_sma_handle = iMA(_Symbol, SelectedTimeframe, AD_SMA_Period, 0, MODE_SMA, ad_handle);

   if (cci_handle == INVALID_HANDLE || obv_handle == INVALID_HANDLE || ad_handle == INVALID_HANDLE ||
       obv_sma_handle == INVALID_HANDLE || ad_sma_handle == INVALID_HANDLE)
   {
      Print("Lỗi khi khởi tạo chỉ báo: ", GetLastError());
      return INIT_FAILED;
   }

   ArraySetAsSeries(cci_buffer, true);
   ArraySetAsSeries(obv_buffer, true);
   ArraySetAsSeries(ad_buffer, true);
   ArraySetAsSeries(obv_sma_buffer, true);
   ArraySetAsSeries(ad_sma_buffer, true);

   return INIT_SUCCEEDED;
}
bool IsBarClosing()
{
   datetime barTime = iTime(_Symbol, SelectedTimeframe, 0);
   int periodSec = PeriodSeconds(SelectedTimeframe);
   if (TimeCurrent() >= barTime + periodSec - 1)
      return true;
   return false;
}

bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, SelectedTimeframe, 0);
   if (currentBarTime == lastBarTime)
      return false;
   lastBarTime = currentBarTime;
   return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(cci_handle);
   IndicatorRelease(obv_handle);
   IndicatorRelease(ad_handle);
   IndicatorRelease(obv_sma_handle);
   IndicatorRelease(ad_sma_handle);
   Print(GenerateComment("Deinitialized"));
}
//+------------------------------------------------------------------+
//| Fubnction calculate volumn                                       |
//+------------------------------------------------------------------+

double CalculateLotSize(double entryPrice, double stopLoss)
{
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if (stopLoss <= 0 || entryPrice <= 0 || stopLoss == entryPrice || contractSize <= 0)
      return 0.0;

   double lotSize = riskMoney / (MathAbs(entryPrice - stopLoss) * contractSize);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if (maxLot > 0)
      lotSize = fmin(lotSize, maxLot);

   lotSize = NormalizeDouble(floor(lotSize / lotStep) * lotStep, 2);

   lotSize = fmax(lotSize, minLot);

   PrintFormat("LotSize: %.2f | Risk: $%.2f | Entry: %.2f | SL: %.2f | Contract Size: %.2f | MaxLot: %.2f",
               lotSize, riskMoney, entryPrice, stopLoss, contractSize, maxLot);
   return lotSize;
}
//+------------------------------------------------------------------+
//| Evaluate trading signals based on price and moving averages      |
//+------------------------------------------------------------------+

TradingSignals EvaluateTradingSignals(double closePrice)
{
   TradingSignals signals = {false, false, false, false};

   double entryCCI = cci_buffer[1];
   double currentCCI = cci_buffer[0];

   bool obv_above_sma = obv_buffer[1] > obv_sma_buffer[1];
   bool ad_above_sma = ad_buffer[1] > ad_sma_buffer[1];
   bool obv_below_sma = obv_buffer[1] < obv_sma_buffer[1];
   bool ad_below_sma = ad_buffer[1] < ad_sma_buffer[1];

   signals.buy = obv_above_sma && ad_above_sma && entryCCI > CciBuy;
   signals.sell = obv_below_sma && ad_below_sma && currentCCI < CciSell;

   signals.closeBuy = entryCCI < CciBuy;
   signals.closeSell = entryCCI > CciSell;

   return signals;
}

//+------------------------------------------------------------------+
//| Function copy indicator                                          |
//+------------------------------------------------------------------+
bool CopyIndicatorBuffers()
{
   if (CopyBuffer(cci_handle, 0, 0, 3, cci_buffer) < 0 ||
       CopyBuffer(obv_handle, 0, 0, 3, obv_buffer) < 0 ||
       CopyBuffer(ad_handle, 0, 0, 3, ad_buffer) < 0 ||
       CopyBuffer(obv_sma_handle, 0, 0, 3, obv_sma_buffer) < 0 ||
       CopyBuffer(ad_sma_handle, 0, 0, 3, ad_sma_buffer) < 0)
   {
      Print("Lỗi khi sao chép buffer chỉ báo: ", GetLastError());
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
//| General handling of OnTick             |
//+------------------------------------------------------------------+
void ProcessTickCommon(int shift)
{
   double closePrice = iClose(_Symbol, SelectedTimeframe, shift);

   if (!CopyIndicatorBuffers())
      return;

   if (ArraySize(cci_buffer) < 3)
      return;

   bool has_position = PositionSelect(_Symbol);
   bool is_buy = has_position && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   TradingSignals signals = EvaluateTradingSignals(closePrice);

   if (!has_position)
   {
      if (AcceptBuy && signals.buy)
      {
         double stop_loss = FindDynamicStopLoss(true);
         if (stop_loss > 0)
            TryOpenOrder(ORDER_TYPE_BUY, stop_loss);
      }

      if (AcceptSell && signals.sell)
      {
         double stop_loss = FindDynamicStopLoss(false);
         if (stop_loss > 0)
            TryOpenOrder(ORDER_TYPE_SELL, stop_loss);
      }
   }
   else
   {
      if ((is_buy && signals.closeBuy) || (!is_buy && signals.closeSell))
         CloseOrders(is_buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   }
}
//+------------------------------------------------------------------+
//| Get  last price close function                                   |
//+------------------------------------------------------------------+
double GetLastClosedPrice()
{
   if (!HistorySelect(0, TimeCurrent()))
   {
      Print("Lỗi khi tải lịch sử giao dịch!");
      return 0;
   }

   ulong last_deal_ticket = 0;
   datetime last_close_time = 0;

   int total = HistoryDealsTotal();
   for (int i = 0; i < total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if (deal_ticket > 0)
      {
         datetime close_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         if (close_time > last_close_time)
         {
            last_close_time = close_time;
            last_deal_ticket = deal_ticket;
         }
      }
   }

   if (last_deal_ticket > 0)
   {
      double close_price = HistoryDealGetDouble(last_deal_ticket, DEAL_PRICE);
      PrintFormat("Last closed price: %.5f", close_price);
      return close_price;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| find stoploss tick function                                      |
//+------------------------------------------------------------------+
double FindDynamicStopLoss(bool isBuy)
{
   double lastExitPrice = GetLastClosedPrice();
   int lastExitBarIndex = iBarShift(_Symbol, SelectedTimeframe, TimeCurrent(), true) - iBarShift(_Symbol, SelectedTimeframe, lastExitPrice, true);

   if (lastExitBarIndex < NumbberOfBars)
      lastExitPrice = 0;

   MqlRates price_data[];
   ArraySetAsSeries(price_data, true);
   if (CopyRates(_Symbol, SelectedTimeframe, 0, 100, price_data) <= 0)
      return -1;

   ArraySetAsSeries(cci_buffer, true);
   if (cci_handle == INVALID_HANDLE || CopyBuffer(cci_handle, 0, 0, 100, cci_buffer) <= 0)
      return -1;

   double stopLoss = isBuy ? price_data[0].low : price_data[0].high;
   bool foundZone = false;

   for (int i = 1; i < 100; i++)
   {
      if (lastExitPrice > 0)
      {
         if ((isBuy && price_data[i].low <= lastExitPrice) || (!isBuy && price_data[i].high >= lastExitPrice))
            continue;
      }

      if (isBuy)
      {
         if (!foundZone && cci_buffer[i] < CciBuy)
            foundZone = true;

         if (foundZone)
            stopLoss = fmin(stopLoss, price_data[i].low);
      }
      else
      {
         if (!foundZone && cci_buffer[i] > CciSell)
            foundZone = true;

         if (foundZone)
            stopLoss = fmax(stopLoss, price_data[i].high);
      }

      if (foundZone && i > NumbberOfBars)
         break;
   }

   return stopLoss;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Nếu OrderEntryOption là ENTRY_ATC, xử lý khi nến hiện tại sắp đóng
   if (OrderEntryOption == ENTRY_ATC)
   {
      if (!IsBarClosing())
         return; // Chưa đến thời điểm đóng nến
      ProcessTickCommon(0);
   }
   else
   {
      // Với các loại lệnh khác, xử lý khi có nến mới
      if (!IsNewBar())
         return;
      ProcessTickCommon(1);
   }
}

//+------------------------------------------------------------------+
//| Check have trade open function                                   |
//+------------------------------------------------------------------+
bool IsTradeOpen(int type)
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         int positionType = PositionGetInteger(POSITION_TYPE);
         if (positionType == type)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
//| OpenTrade function                                               |
//+------------------------------------------------------------------+
void ExecuteOrders(ENUM_ORDER_TYPE orderType, double entryPrice, double stop_loss, double lotSize, string comment)
{
   if ((orderType == ORDER_TYPE_BUY && IsTradeOpen(POSITION_TYPE_BUY)) ||
       (orderType == ORDER_TYPE_SELL && IsTradeOpen(POSITION_TYPE_SELL)))
   {
      return;
   }
   while (lotSize > 0)
   {
      double lotToTrade = fmin(lotSize, maxLotSize);

      trade.SetExpertMagicNumber(MagicNumber);
      trade.SetDeviationInPoints(10);
      trade.SetTypeFilling(ORDER_FILLING_FOK);

      bool result = false;
      if (orderType == ORDER_TYPE_BUY)
         result = trade.Buy(lotToTrade, _Symbol, 0, stop_loss, 0, comment);
      else if (orderType == ORDER_TYPE_SELL)
         result = trade.Sell(lotToTrade, _Symbol, 0, stop_loss, 0, comment);

      if (result)
      {
         Print(comment, " order opened successfully - Lot: ", lotToTrade);
      }
      else
      {
         Print("Error opening ", comment, " order: ", trade.ResultRetcode(), " - ", GetLastError());
         break;
      }

      lotSize -= lotToTrade;
   }
}
//+------------------------------------------------------------------+
//| Open  function                                                     |
//+------------------------------------------------------------------+
void TryOpenOrder(ENUM_ORDER_TYPE orderType, double stop_loss)
{
   double entryPrice;
   if (orderType == ORDER_TYPE_BUY)
   {
      if (OrderEntryOption == ENTRY_ATO || OrderEntryOption == ENTRY_ATC)
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else if (OrderEntryOption == ENTRY_LIMIT_PREV_CLOSE)
         entryPrice = iClose(_Symbol, SelectedTimeframe, 1);
      else
         entryPrice = iOpen(_Symbol, SelectedTimeframe, 0);
   }
   else
   {
      if (OrderEntryOption == ENTRY_ATO || OrderEntryOption == ENTRY_ATC)
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      else if (OrderEntryOption == ENTRY_LIMIT_PREV_CLOSE)
         entryPrice = iClose(_Symbol, SelectedTimeframe, 1);
      else
         entryPrice = iOpen(_Symbol, SelectedTimeframe, 0);
   }
   double qty = CalculateLotSize(entryPrice, stop_loss);
   if (qty > 0.0)
      ExecuteOrders(orderType, entryPrice, stop_loss, qty, GenerateComment((orderType == ORDER_TYPE_BUY) ? "Buy Order" : "Sell Order"));
}
//+------------------------------------------------------------------+
//| Generate a comment string by concatenating input values          |
//| Format: MagicNumber_LossPerOrder_LotThreshold_TimeFrame_baseComment|
//+------------------------------------------------------------------+
string GenerateComment(string baseComment)
{
   string tfStr = "";
   if (SelectedTimeframe == PERIOD_M1)
      tfStr = "M1";
   else if (SelectedTimeframe == PERIOD_M5)
      tfStr = "M5";
   else if (SelectedTimeframe == PERIOD_M15)
      tfStr = "15m";
   else if (SelectedTimeframe == PERIOD_M30)
      tfStr = "30m";
   else if (SelectedTimeframe == PERIOD_H1)
      tfStr = "H1";
   else if (SelectedTimeframe == PERIOD_H4)
      tfStr = "H4";
   else if (SelectedTimeframe == PERIOD_D1)
      tfStr = "D1";
   else if (SelectedTimeframe == PERIOD_W1)
      tfStr = "W1";
   else if (SelectedTimeframe == PERIOD_MN1)
      tfStr = "MN1";
   else
      tfStr = "Unknown";
   return (IntegerToString(MagicNumber) + "_" + DoubleToString(riskMoney, 0) + "_" +
           DoubleToString(maxLot, 0) + "_" + tfStr + "_" + baseComment);
}

//+------------------------------------------------------------------+
//| Close  function                                               |
//+------------------------------------------------------------------+
void CloseOrders(ENUM_POSITION_TYPE typeToClose)
{
   int totalPositions = PositionsTotal();
   
   trade.SetComment("Closing position");
   
   for(int i = totalPositions - 1; i >= 0; i--)
   {
       ulong ticket = PositionGetTicket(i);
       
       if(PositionSelectByTicket(ticket))
       {
           if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
              PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
              PositionGetInteger(POSITION_TYPE) == typeToClose)
           {
              if(!trade.PositionClose(ticket))
                 Print(GenerateComment("Failed to close "), 
                      (typeToClose == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                      " position with ticket: ", ticket,
                      ". Error: ", GetLastError());
           }
       }
   }
}