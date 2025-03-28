MqlTradeResult m_result;            // result data
MqlTradeCheckResult m_check_result; // result check data
ulong m_deviation;                  // deviation default
ENUM_ORDER_TYPE_FILLING m_type_filling;
MqlTradeRequest m_request; // request data
input ENUM_TIMEFRAMES SelectedTimeframe = PERIOD_M15; // Timeframe to use for the indicator
input double maxLot = 0;                              // Max Lot Size user can trade (if = 0 Lot vô hạn)
input int MagicNumber = 12345;                        // Magic Number
input double riskMoney = 1000;                        // Risk Money



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
   for (int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
          PositionGetInteger(POSITION_TYPE) == typeToClose)
      {
         string closeComment = "Closing position";
         if (!PositionClose(ticket, m_deviation, GenerateComment(closeComment)))
         {
            PrintFormat("Failed to close %s position with ticket: %d. Error: %d",
                        (typeToClose == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                        ticket, GetLastError());
         }
      }
   }
}

bool PositionClose(const ulong ticket, const ulong deviation, string comment)
{
   if (IsStopped())
      return false;

   if (!PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ClearStructures();

   if (!FillingCheck(symbol))
      return false;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   m_request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   m_request.price = (posType == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(symbol, SYMBOL_BID)
                         : SymbolInfoDouble(symbol, SYMBOL_ASK);
   m_request.action = TRADE_ACTION_DEAL;
   m_request.position = ticket;
   m_request.symbol = symbol;
   m_request.volume = PositionGetDouble(POSITION_VOLUME);
   m_request.magic = MagicNumber;
   m_request.deviation = (deviation == ULONG_MAX) ? m_deviation : deviation;
   m_request.comment = comment; // Thêm comment

   if (!OrderSend(m_request, m_result))
   {
      PrintFormat("OrderSend failed: %d", m_result.retcode);
      return false;
   }

   PrintFormat("Order closed: Ticket=%d, Comment=%s, ResultCode=%d", ticket, comment, m_result.retcode);

   return (m_result.retcode == TRADE_RETCODE_DONE);
}

bool IsStopped(const string function)
{
   if (!::IsStopped())
      return (false);
   PrintFormat("%s: MQL5 program is stopped. Trading is disabled", function);
   m_result.retcode = TRADE_RETCODE_CLIENT_DISABLES_AT;
   return (true);
}
void ClearStructures(void)
{
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   ZeroMemory(m_check_result);
}

//+------------------------------------------------------------------+
//| Checks and corrects type of filling policy                       |
//+------------------------------------------------------------------+
bool FillingCheck(const string symbol)
{
   //--- get execution mode of orders by symbol
   ENUM_SYMBOL_TRADE_EXECUTION exec = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   //--- check execution mode
   if (exec == SYMBOL_TRADE_EXECUTION_REQUEST || exec == SYMBOL_TRADE_EXECUTION_INSTANT)
   {
      //--- neccessary filling type will be placed automatically
      return (true);
   }
   //--- get possible filling policy types by symbol
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   //--- check execution mode again
   if (exec == SYMBOL_TRADE_EXECUTION_MARKET)
   {
      //--- for the MARKET execution mode
      //--- analyze order
      if (m_request.action != TRADE_ACTION_PENDING)
      {
         //--- in case of instant execution order
         //--- if the required filling policy is supported, add it to the request
         if ((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         {
            m_type_filling = ORDER_FILLING_FOK;
            m_request.type_filling = m_type_filling;
            return (true);
         }
         if ((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         {
            m_type_filling = ORDER_FILLING_IOC;
            m_request.type_filling = m_type_filling;
            return (true);
         }
         //--- wrong filling policy, set error code
         m_result.retcode = TRADE_RETCODE_INVALID_FILL;
         return (false);
      }
      return (true);
   }
   //--- EXCHANGE execution mode
   switch (m_type_filling)
   {
   case ORDER_FILLING_FOK:
      //--- analyze order
      if (m_request.action == TRADE_ACTION_PENDING)
      {
         //--- in case of pending order
         //--- add the expiration mode to the request
         if (!ExpirationCheck(symbol))
            m_request.type_time = ORDER_TIME_DAY;
         //--- stop order?
         if (m_request.type == ORDER_TYPE_BUY_STOP || m_request.type == ORDER_TYPE_SELL_STOP ||
             m_request.type == ORDER_TYPE_BUY_LIMIT || m_request.type == ORDER_TYPE_SELL_LIMIT)
         {
            //--- in case of stop order
            //--- add the corresponding filling policy to the request
            m_request.type_filling = ORDER_FILLING_RETURN;
            return (true);
         }
      }
      //--- in case of limit order or instant execution order
      //--- if the required filling policy is supported, add it to the request
      if ((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      {
         m_request.type_filling = m_type_filling;
         return (true);
      }
      //--- wrong filling policy, set error code
      m_result.retcode = TRADE_RETCODE_INVALID_FILL;
      return (false);
   case ORDER_FILLING_IOC:
      //--- analyze order
      if (m_request.action == TRADE_ACTION_PENDING)
      {
         //--- in case of pending order
         //--- add the expiration mode to the request
         if (!ExpirationCheck(symbol))
            m_request.type_time = ORDER_TIME_DAY;
         //--- stop order?
         if (m_request.type == ORDER_TYPE_BUY_STOP || m_request.type == ORDER_TYPE_SELL_STOP ||
             m_request.type == ORDER_TYPE_BUY_LIMIT || m_request.type == ORDER_TYPE_SELL_LIMIT)
         {
            //--- in case of stop order
            //--- add the corresponding filling policy to the request
            m_request.type_filling = ORDER_FILLING_RETURN;
            return (true);
         }
      }
      //--- in case of limit order or instant execution order
      //--- if the required filling policy is supported, add it to the request
      if ((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      {
         m_request.type_filling = m_type_filling;
         return (true);
      }
      //--- wrong filling policy, set error code
      m_result.retcode = TRADE_RETCODE_INVALID_FILL;
      return (false);
   case ORDER_FILLING_RETURN:
      //--- add filling policy to the request
      m_request.type_filling = m_type_filling;
      return (true);
   }
   //--- unknown execution mode, set error code
   m_result.retcode = TRADE_RETCODE_ERROR;
   return (false);
}
bool ExpirationCheck(const string symbol)
{
   //--- check symbol
   string symbol_name = (symbol == NULL) ? _Symbol : symbol;
   //--- get flags
   long tmp_long;
   int flags = 0;
   if (SymbolInfoInteger(symbol_name, SYMBOL_EXPIRATION_MODE, tmp_long))
      flags = (int)tmp_long;
   switch (m_request.type_time)
   {
   case ORDER_TIME_GTC:
      if ((flags & SYMBOL_EXPIRATION_GTC) != 0)
         return (true);
      break;
   case ORDER_TIME_DAY:
      if ((flags & SYMBOL_EXPIRATION_DAY) != 0)
         return (true);
      break;
   case ORDER_TIME_SPECIFIED:
      if ((flags & SYMBOL_EXPIRATION_SPECIFIED) != 0)
         return (true);
      break;
   case ORDER_TIME_SPECIFIED_DAY:
      if ((flags & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0)
         return (true);
      break;
   default:
      Print(__FUNCTION__ + ": Unknown expiration type");
   }
   return (false);
}