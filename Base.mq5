//+------------------------------------------------------------------+
//|                        Copyright 2024, Leslie                    |
//|                        https://LotusQuant.com                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2025, LotusQuant"
#property link "https://LotusQuant.com"
#property version "1.00"
#include <Trade/Trade.mqh>

class CTradeEx : public CTrade
{
public:
   bool PositionClose(const ulong ticket, const string m_comment = "", const ulong deviation = ULONG_MAX)
   {
      //--- check stopped
      if (IsStopped(__FUNCTION__))
         return (false);
      //--- check position existence
      if (!PositionSelectByTicket(ticket))
         return (false);
      string symbol = PositionGetString(POSITION_SYMBOL);
      //--- clean
      ClearStructures();
      //--- check filling
      if (!FillingCheck(symbol))
         return (false);
      //--- check
      if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
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

      // Add comment to request
      m_request.comment = m_comment;

      //--- close position
      return (OrderSend(m_request, m_result));
   }
};
CTradeEx trade;
// Define the OrderEntryMode enumeration
enum OrderEntryMode
{
   ENTRY_ATO,             // At the open
   ENTRY_ATC,             // At the close
   ENTRY_LIMIT_PREV_CLOSE // Limit at previous close
};

struct TradingSignals
{
   bool buy;
   bool sell;
   bool closeBuy;
   bool closeSell;
};


input double lotThreshold = 0;                       // Maximum lot size, 0 has no effect
input long MagicNumber = 123456;                     // Magic number for the EA
input double riskMoney = 1000;                       // Risk Money
input bool AcceptBuy = true;                         // Enable Buy Orders
input bool AcceptSell = false;                       // Enable Sell Orders
input ENUM_TIMEFRAMES SelectedTimeframe = PERIOD_H1; // Selected Timeframe for the EA
input OrderEntryMode OrderEntryOption = ENTRY_ATO;   // Choose entry mode
datetime lastBarTime = iTime(_Symbol, SelectedTimeframe, 0);


void ExecuteOrders(ENUM_ORDER_TYPE orderType, double qty, double stop_loss, double entryPrice)
{
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double limitLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if ((limitLot > lotThreshold || limitLot == 0) && lotThreshold > 0)
      limitLot = lotThreshold;
   if (limitLot > 0 && qty > limitLot)
   {
      qty = limitLot;
   }
   if (maxLot == 0)
      maxLot = qty;
   while (qty > 0)
   {
      double lotToTrade = (qty > maxLot) ? maxLot : qty;

      if (orderType == ORDER_TYPE_BUY)
         trade.Buy(lotToTrade, _Symbol, entryPrice, stop_loss, 0, GenerateComment("Buy Order"));
      else
         trade.Sell(lotToTrade, _Symbol, entryPrice, stop_loss, 0, GenerateComment("Sell Order"));
      qty -= lotToTrade;
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
   double CSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double riskDistance = MathAbs(entryPrice - stop_loss);
   double qty = CalculateLotSize(entryPrice, stop_loss);
   if (qty > 0.0)
      ExecuteOrders(orderType, qty, stop_loss, entryPrice);
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
           DoubleToString(lotThreshold, 0) + "_" + tfStr + "_" + baseComment);
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

   lotSize = NormalizeDouble(MathRound(lotSize / lotStep) * lotStep, 2);

   lotSize = fmax(lotSize, minLot);

   return lotSize;
}

//+------------------------------------------------------------------+
//| Close  function                                                  |
//+------------------------------------------------------------------+
void CloseOrders(ENUM_POSITION_TYPE typeToClose)
{
   int totalPositions = PositionsTotal();
   for (int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
             PositionGetInteger(POSITION_TYPE) == typeToClose)
         {
            if (!trade.PositionClose(ticket,
                                     GenerateComment("Close Order")))
               Print(GenerateComment("Failed to close "),
                     (typeToClose == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     " position with ticket: ", ticket,
                     ". Error: ", GetLastError());
         }
      }
   }
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
