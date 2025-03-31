//+------------------------------------------------------------------+
//|                        All In One MA Cross.mq5                   |
//|                        Copyright 2024, Leslie                    |
//|                        https://LotusQuant.com                    |
//+------------------------------------------------------------------+
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

struct TradingSignals
{
   bool buy;
   bool sell;
   bool closeBuy;
   bool closeSell;
};
enum enPrices
{
   pr_close   = PRICE_CLOSE,
   pr_open    = PRICE_OPEN,
   pr_high    = PRICE_HIGH,
   pr_low     = PRICE_LOW,
   pr_median  = PRICE_MEDIAN,
   pr_typical = PRICE_TYPICAL,
   pr_weighted= PRICE_WEIGHTED
};

enum OrderEntryMode
{
   ENTRY_ATO,              // At the open
   ENTRY_ATC,              // At the close
   ENTRY_LIMIT_PREV_CLOSE, // Limit at previous close
   ENTRY_LIMIT_PREV_OPEN   // Limit at previous open
};

input int AvgPeriod = 20;               // Volume weighted average period
input bool UseRealVolume = false;       // Use real volume?
input bool DeviationSample = false;     // Deviation with sample correction?
input double DeviationMuliplier1 = 1;   // First band(s) deviation
input double DeviationMuliplier2 = 2;   // Second band(s) deviation
input double DeviationMuliplier3 = 2.5; // Third band(s) deviation
input int OBV_MA_Period = 5;            //  MA Period
input ENUM_APPLIED_PRICE SMA_Apply = PRICE_TYPICAL; // SMA Apply To
input ENUM_MA_METHOD ma_method = MODE_SMA;
input bool AcceptBuy = true;   // Enable Buy Orders
input bool AcceptSell = false; // Enable Sell Orders
// Define the OrderEntryMode enumeration
input ENUM_TIMEFRAMES SelectedTimeframe = PERIOD_M15;
input OrderEntryMode OrderEntryOption = ENTRY_ATO; // Choose entry mode
input int MagicNumber = 12345;                        // Magic Number
input double riskMoney = 1000;                        // Risk Money
input double maxLot = 0;                              // Max Lot Size user can trade (if = 0 no limited)
double Band1[], Band2[], Band3[], 
Band4[], Band5[], 
Band6[], Band7[],SMA[];
int wwap_hand;
int MA_handle;

input enPrices Price = pr_close;
datetime lastBarTime = iTime(_Symbol, SelectedTimeframe, 0);
double maxLotSize;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   wwap_hand = iCustom(Symbol(), SelectedTimeframe, "VWAP_Bands",
   AvgPeriod,            
   Price,   
   UseRealVolume,         
   DeviationSample,         
   DeviationMuliplier1,           
   DeviationMuliplier2,           
   DeviationMuliplier3);         
   MA_handle = iMA(_Symbol, SelectedTimeframe, OBV_MA_Period, 0, ma_method, SMA_Apply);


   if (wwap_hand == INVALID_HANDLE)
   {
      Print("Lỗi: Không thể khởi tạo chỉ báo VWAP Bands!");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (wwap_hand != INVALID_HANDLE)
   {
      IndicatorRelease(wwap_hand);
   }
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


void ProcessTickCommon(int shift)
{

   
   bool has_position = PositionSelect(_Symbol);
   // kiểu tra xem lệnh là buy hay sell
   bool is_buy = has_position && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   TradingSignals signals = EvaluateTradingSignals(shift);
if (!has_position)
   {
      trade.SetExpertMagicNumber(MagicNumber);  
      trade.SetDeviationInPoints(10);
      trade.SetTypeFilling(ORDER_FILLING_FOK);
      if (AcceptBuy && signals.buy)
      {
         // Tính stoploss của lệnh buy
         double stop_loss = FindDynamicStopLoss(ORDER_TYPE_BUY, 1,shift);
         Print("stop_loss: ", stop_loss);

         if (stop_loss > 0){
            double entryPrice = iClose(_Symbol, SelectedTimeframe, 1);
            double lotSize = CalculateLotSize(entryPrice, stop_loss);
            trade.Buy(lotSize, _Symbol, 0, stop_loss, 0, "Buy Order");
         }
            // TryOpenOrder(ORDER_TYPE_BUY, stop_loss);

      }

      if (AcceptSell && signals.sell)
      {
         // Tính stoploss của lệnh sell
         double stop_loss = FindDynamicStopLoss(ORDER_TYPE_SELL, 6,shift); 
         Print("stop_loss: ", stop_loss);
         double entryPrice = iClose(_Symbol, SelectedTimeframe, 1);
         double lotSize = CalculateLotSize(entryPrice, stop_loss);
         if (stop_loss > 0){
            trade.Sell(lotSize, _Symbol, 0, stop_loss, 0, "Sell Order");
         }
         // TryOpenOrder(ORDER_TYPE_SELL, stop_loss);
         
      }
   }
   else
   {
      if (is_buy && signals.closeBuy)
      {
         Print("Close Buy Order");
         CloseOrders(POSITION_TYPE_BUY);
      }

      if (!is_buy && signals.closeSell)
      {
         CloseOrders(POSITION_TYPE_SELL);
      }

   }
}

TradingSignals EvaluateTradingSignals(int shift)
{
   TradingSignals signals = {false, false, false, false};
   if (!CopyIndicatorBuffers(shift))
      return signals;

   double closePrice = iClose(_Symbol, SelectedTimeframe, shift);
   double prevClosePrice = iClose(_Symbol, SelectedTimeframe, shift + 1);

   double middleVWAP = Band4[shift];
   double prevMiddleVWAP = Band4[shift + 1];
   double smaValue = SMA[shift];
   double band7 = Band7[shift];  
   double band1 = Band1[shift];  

   if (closePrice > smaValue && prevClosePrice <= prevMiddleVWAP && closePrice > middleVWAP)
   {
      signals.buy = true;
   }

   if (closePrice < smaValue && prevClosePrice >= prevMiddleVWAP && closePrice < middleVWAP)
   {
      signals.sell = true;
   }

   if ((prevClosePrice <= band1 && closePrice > band1) || (prevClosePrice > middleVWAP && closePrice < middleVWAP))
   {
      signals.closeBuy = true;
   }
   if ((prevClosePrice >= band7 && closePrice < band7) || (prevClosePrice < middleVWAP && closePrice > middleVWAP))
   {
      signals.closeSell = true;
   }
   

   return signals;
}


bool CopyIndicatorBuffers(int shift)
{
   ArraySetAsSeries(Band1, true);
   ArraySetAsSeries(Band2, true);
   ArraySetAsSeries(Band3, true);
   ArraySetAsSeries(Band4, true);
   ArraySetAsSeries(Band5, true);
   ArraySetAsSeries(Band6, true);
   ArraySetAsSeries(Band7, true);
   ArraySetAsSeries(SMA, true);

   if (CopyBuffer(wwap_hand, 0, shift, 3, Band1) <= 0 ||
       CopyBuffer(wwap_hand, 1, shift, 3, Band2) <= 0 ||
       CopyBuffer(wwap_hand, 2, shift, 3, Band3) <= 0 ||
       CopyBuffer(wwap_hand, 3, shift, 3, Band4) <= 0 ||
       CopyBuffer(wwap_hand, 4, shift, 3, Band5) <= 0 ||
       CopyBuffer(wwap_hand, 5, shift, 3, Band6) <= 0 ||
       CopyBuffer(wwap_hand, 6, shift, 3, Band7) <= 0 ||
       CopyBuffer(MA_handle, 0, shift, 3, SMA) <= 0)
   {
      Print("Lỗi: Không thể lấy dữ liệu từ chỉ báo!");
      return false;
   }
   return true;
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

double FindDynamicStopLoss(ENUM_ORDER_TYPE orderType, int bandOption, int shift)
{
   if (!CopyIndicatorBuffers(shift))
   {
      Print(" Lỗi khi lấy dữ liệu band!");
      return 0;
   }

   double stop_loss = 0;

   if (orderType == ORDER_TYPE_BUY)
   {
      if (bandOption == 1) stop_loss = Band5[shift];
      else if (bandOption == 2) stop_loss = Band6[shift];
      else if (bandOption == 3) stop_loss = Band7[shift];
      else
      {
         return 0;
      }
   }
   else if (orderType == ORDER_TYPE_SELL)
   {
      if (bandOption == 5) stop_loss = Band1[shift];
      else if (bandOption == 6) stop_loss = Band2[shift];
      else if (bandOption == 7) stop_loss = Band3[shift];
      else
      {
         return 0;
      }
   }
   else
   {
      Print(" OrderType không hợp lệ!");
      return 0;
   }

   return stop_loss; 
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
   Print("Entry Price: ", entryPrice);
   Print("VOLUMN: ", qty);

   if (qty > 0.0)
   ExecuteOrders(orderType, entryPrice, stop_loss,qty, GenerateComment((orderType == ORDER_TYPE_BUY) ? "Buy Order" : "Sell Order"));
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

//+------------------------------------------------------------------+
//| Close  function                                                  |
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