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

void CloseOrders(ENUM_POSITION_TYPE typeToClose)
{
   int MagicNumber = 123456; // Example Magic Number
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
string GenerateComment(string baseComment)
{
   int MagicNumber = 123456; // Example Magic Number
   int maxLot = 0; // Example Max Lot
   double riskMoney = 1000.0; // Example Risk Money
   int SelectedTimeframe = PERIOD_H1; // Example Timeframe
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


// MagicNumber khai bao
// riskMoney so tiền sẵn sàng mất cho 1 lệnh ;
// maxLot số lot tối đa cho 1 lệnh ( nếu bằng 0 thì ko giới hạn )