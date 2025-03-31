//+------------------------------------------------------------------+
//|                        Copyright 2024, Leslie                    |
//|                        https://LotusQuant.com                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, LotusQuant"
#property link "https://LotusQuant.com"
#property version "1.00"
#include <Trade/Trade.mqh>

//--- Input parameters
input int MFI_Period = 14;                            // MFI Period
input int OBV_MA_Period = 5;                          // OBV MA Period
input int MagicNumber = 12345;                        // Magic Number
input double riskMoney = 1000;                        // Risk Money
input double maxLot = 0;                              // Max Lot Size user can trade
input ENUM_TIMEFRAMES SelectedTimeframe = PERIOD_M15; // Timeframe to use for the indicator
input double mfiTarget = 50;                          // MFI target level

// Define ENUM_TRADE_MODE if not already defined

input bool AcceptBuy = true;   // Enable Buy Orders
input bool AcceptSell = false; // Enable Sell Orders// Define the OrderEntryMode enumeration
enum OrderEntryMode
{
   ENTRY_ATO,              // At the open
   ENTRY_ATC,              // At the close
   ENTRY_LIMIT_PREV_CLOSE, // Limit at previous close
   ENTRY_LIMIT_PREV_OPEN   // Limit at previous open
};
struct TradingSignals
{
   bool buy;
   bool sell;
   bool closeBuy;
   bool closeSell;
};

input OrderEntryMode OrderEntryOption = ENTRY_ATO; // Choose entry mode
double obv[], obvMA[], mfi[];
double stopLoss;
double maxLotSize;
double LotSize = 0.0;
int obv_handle;
int mfi_handle;
int obvMA_handle;
datetime lastBarTime = iTime(_Symbol, SelectedTimeframe, 0);

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
//| Initialization function                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   obv_handle = iOBV(_Symbol, SelectedTimeframe, VOLUME_TICK);
   mfi_handle = iMFI(_Symbol, SelectedTimeframe, MFI_Period, VOLUME_TICK);
   obvMA_handle = iMA(_Symbol, SelectedTimeframe, OBV_MA_Period, 0, MODE_SMA, obv_handle);

   if (obv_handle == INVALID_HANDLE || mfi_handle == INVALID_HANDLE || obvMA_handle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   maxLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick function                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   // Nếu OrderEntryOption là ENTRY_ATC, xử lý khi nến hiện tại sắp đóng
   if (OrderEntryOption == ENTRY_ATC)
   {
      if (!IsBarClosing())
         return; // Chưa đến thời điểm đóng nến
      ProcessTickCommon();
   }
   else
   {
      // Với các loại lệnh khác, xử lý khi có nến mới
      if (!IsNewBar())
         return;
      ProcessTickCommon();
   }
}
//+------------------------------------------------------+
//| Hàm sao chép buffer từ indicator                     |
//+------------------------------------------------------+
bool CopyIndicatorBuffers()
{
   ArraySetAsSeries(obv, true);
   ArraySetAsSeries(obvMA, true);
   ArraySetAsSeries(mfi, true);
   if (CopyBuffer(obv_handle, 0, 0, 3, obv) <= 0 ||
       CopyBuffer(mfi_handle, 0, 0, 3, mfi) <= 0 ||
       CopyBuffer(obvMA_handle, 0, 0, 3, obvMA) <= 0)
   {
      Print("Lỗi khi sao chép buffer chỉ báo: ", GetLastError());
      return false;
   }

   int size = ArraySize(obv);
   if (size < 3)
   {
      Print("Không đủ dữ liệu để kiểm tra tín hiệu.");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Evaluate Trading Signals                                          |
//+------------------------------------------------------------------+
TradingSignals EvaluateTradingSignals()
{
   TradingSignals signals = {false, false, false, false};

   if (!CopyIndicatorBuffers())
      return signals;

   int size = ArraySize(obv);

   double obv_current = obv[1];
   double obv_prev = obv[2];

   double obvMA_current = obvMA[1];
   double obvMA_prev = obvMA[2];
   
   double entryMFI = mfi[0];

   if (entryMFI > mfiTarget)
   {
      signals.buy = (obv_prev <= obvMA_prev && obv_current > obvMA_current);
   }

   if (entryMFI > mfiTarget)
   {
      signals.sell = (obv_prev >= obvMA_prev && obv_current < obvMA_current);
   }

   if (PositionSelect(_Symbol))
   {
      bool is_buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      signals.closeBuy = is_buy && (obv_prev >= obvMA_prev && obv_current < obvMA_current);
      signals.closeSell = !is_buy && (obv_prev <= obvMA_prev && obv_current > obvMA_current);
   }
   return signals;
}
//+------------------------------------------------------------------+
//| Xử lý chung của OnTick                                           |
//+------------------------------------------------------------------+

void ProcessTickCommon()
{
   // đã có lệnh vào chưa
   bool has_position = PositionSelect(_Symbol);
   // kiểu tra xem lệnh là buy hay sell
   bool is_buy = has_position && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   // Đánh giá tín hiệu giao dịch dựa trên giá hiện tại và các SMA đã tính
   TradingSignals signals = EvaluateTradingSignals();

   if (!has_position)
   {
      if (AcceptBuy && signals.buy)
      {
         // Tính stoploss của lệnh buy
         double stop_loss = FindDynamicStopLoss(true);

         if (stop_loss > 0)
            TryOpenOrder(ORDER_TYPE_BUY, stop_loss);
      }

      if (AcceptSell && signals.sell)
      {
         // Tính stoploss của lệnh sell
         double stop_loss = FindDynamicStopLoss(false);

         if (stop_loss > 0)
            TryOpenOrder(ORDER_TYPE_SELL, stop_loss);
      }
   }
   else
   {
      // Thực hiện đóng/mở lệnh nếu có tín hiệu đảo chiều
      if ((is_buy && signals.closeBuy) || (!is_buy && signals.closeSell))
         CloseOrders(is_buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                     |
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
   // sử dụng hàm CalculateLotSize để tính lotsize
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
//| find stoploss tick function                                      |
//+------------------------------------------------------------------+
double FindDynamicStopLoss(bool isBuy)
{
   MqlRates price_data[];
   if (CopyRates(_Symbol, SelectedTimeframe, 0, 200, price_data) <= 0)
      return isBuy ? price_data[0].low : price_data[0].high;

   double obv_buffer[200], sma_buffer[200];


   if (CopyBuffer(obv_handle, 0, 0, 200, obv_buffer) <= 0 ||
       CopyBuffer(obvMA_handle, 0, 0, 200, sma_buffer) <= 0)
   {
      Print("Lỗi khi lấy dữ liệu chỉ báo OBV hoặc SMA.");
      return isBuy ? price_data[0].low : price_data[0].high;
   }

   int crossStartIndex = -1, crossEndIndex = -1;

   for (int i = 1; i < 200; i++)
   {
      bool isPrevAbove = obv_buffer[i - 1] > sma_buffer[i - 1];
      bool isPrevBelow = obv_buffer[i - 1] < sma_buffer[i - 1];
      bool isCurrAbove = obv_buffer[i] > sma_buffer[i];
      bool isCurrBelow = obv_buffer[i] < sma_buffer[i];

      if (isBuy)
      {
         if (isCurrBelow && crossStartIndex == -1)
            crossStartIndex = i;
         if (crossStartIndex != -1 && isCurrAbove)
         {
            crossEndIndex = i;
            break;
         }
      }
      else
      {
         if (isCurrAbove && crossStartIndex == -1)
            crossStartIndex = i;
         if (crossStartIndex != -1 && isCurrBelow)
         {
            crossEndIndex = i;
            break;
         }
      }
   }

   if (crossStartIndex == -1 || crossEndIndex == -1)
   {
      Print("Không tìm thấy điểm giao cắt.");
      return isBuy ? price_data[0].low : price_data[0].high;
   }

   double stopLoss = isBuy ? price_data[crossStartIndex].low : price_data[crossStartIndex].high;

   for (int i = crossStartIndex; i <= crossEndIndex; i++)
   {
      double price = isBuy ? price_data[i].low : price_data[i].high;
      stopLoss = isBuy ? MathMin(stopLoss, price) : MathMax(stopLoss, price);
   }

   return stopLoss;
}

//+------------------------------------------------------------------+
//| Deinitialization function                                       |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, SelectedTimeframe, 0);
   if (currentBarTime == lastBarTime)
      return false;
   lastBarTime = currentBarTime;
   return true;
}

//+------------------------------------------------------------------+
//| Check if the current bar is about to close                       |
//+------------------------------------------------------------------+
bool IsBarClosing()
{
   datetime barTime = iTime(_Symbol, SelectedTimeframe, 0);
   int periodSec = PeriodSeconds(SelectedTimeframe);
   if (TimeCurrent() >= barTime + periodSec - 1)
      return true;
   return false;
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