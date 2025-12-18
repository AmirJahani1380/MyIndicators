//+------------------------------------------------------------------+
//|                                       FreeScaleIndicator.mq5 |
//|                      Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.20"
#property description "Adds a button to enable/disable TradingView-like vertical chart scaling on the price panel."

//--- This property ensures the indicator runs on the main chart window
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Global variables
// Button settings
string  g_button_name = "FreeScaleButton";
string  g_button_text_on = "ON";
string  g_button_text_off = "OFF";
int     g_button_x_pos = 50;
int     g_button_y_pos = 10;
int     g_button_x_size = 40;
int     g_button_y_size = 20;

// State management
bool    g_is_scaling_enabled = false; // Is the scaling feature active?
bool    g_is_dragging = false;        // Is the user currently dragging the mouse to scale?
int     g_last_mouse_y = 0;           // Last known mouse Y coordinate for calculating drag distance

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Create the ON/OFF button on the chart
    CreateScaleButton();
    
    //--- Tell MetaTrader we want to receive all mouse move and click events
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Clean up: remove the button from the chart
    ObjectDelete(0, g_button_name);
    
    //--- Reset chart scaling to default
    ChartSetInteger(0, CHART_SCALEFIX, 0);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//| This function is not used for this indicator's logic, but is required. |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- We are not calculating any indicator values, so we just return
    return(rates_total);
}

//+------------------------------------------------------------------+
//| ChartEvent function to handle user interactions                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    //--- Check for a click on our button
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_button_name)
    {
        HandleButtonClick();
        return;
    }
    
    //--- Check for mouse movement if scaling is enabled
    if(id == CHARTEVENT_MOUSE_MOVE && g_is_scaling_enabled)
    {
        //--- For CHARTEVENT_MOUSE_MOVE:
        //--- lparam = x-coordinate
        //--- dparam = y-coordinate
        //--- sparam = mouse button & key state string
        
        //--- Get mouse state and position
        bool is_left_button_down = (StringGetCharacter(sparam, 0) == '1');
        long current_mouse_x = lparam;
        int  current_mouse_y = (int)dparam;
        
        //--- Get chart dimensions to locate the price scale area
        long chart_width_pixels;
        ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chart_width_pixels);
        
        //--- Define the width of the price scale area on the right (in pixels)
        int price_scale_area_width = 70;

        //--- Only trigger scaling if the mouse is over the price scale area
        if(current_mouse_x >= chart_width_pixels - price_scale_area_width)
        {
             HandleMouseDrag(is_left_button_down, current_mouse_y);
        }
        else
        {
            // If mouse leaves the active area while dragging, stop the drag action.
            if(g_is_dragging)
            {
                g_is_dragging = false;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Creates and configures the control button.                       |
//+------------------------------------------------------------------+
void CreateScaleButton()
{
    //--- Create the button object
    ObjectCreate(0, g_button_name, OBJ_BUTTON, 0, 0, 0);
    
    //--- Set button properties
    ObjectSetString(0, g_button_name, OBJPROP_TEXT, g_button_text_off);
    ObjectSetInteger(0, g_button_name, OBJPROP_XDISTANCE, g_button_x_pos);
    ObjectSetInteger(0, g_button_name, OBJPROP_YDISTANCE, g_button_y_pos);
    ObjectSetInteger(0, g_button_name, OBJPROP_XSIZE, g_button_x_size);
    ObjectSetInteger(0, g_button_name, OBJPROP_YSIZE, g_button_y_size);
    //--- POSITION UPDATE: Changed from CORNER_LEFT_UPPER to CORNER_RIGHT_UPPER
    ObjectSetInteger(0, g_button_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, g_button_name, OBJPROP_STATE, false);
    ObjectSetInteger(0, g_button_name, OBJPROP_SELECTABLE, false); // Prevent selection
    ObjectSetInteger(0, g_button_name, OBJPROP_ZORDER, 0);
    
    //--- Set colors
    ObjectSetInteger(0, g_button_name, OBJPROP_BGCOLOR, clrLightGray);
    ObjectSetInteger(0, g_button_name, OBJPROP_BORDER_COLOR, clrGray);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Handles the logic when the scale button is clicked.              |
//+------------------------------------------------------------------+
void HandleButtonClick()
{
    //--- Toggle the scaling state
    g_is_scaling_enabled = !g_is_scaling_enabled;
    
    if(g_is_scaling_enabled)
    {
        //--- Enable fixed scaling mode
        ObjectSetString(0, g_button_name, OBJPROP_TEXT, g_button_text_on);
        ObjectSetInteger(0, g_button_name, OBJPROP_BGCOLOR, clrDodgerBlue);
        ObjectSetInteger(0, g_button_name, OBJPROP_STATE, true);
        ChartSetInteger(0, CHART_SCALEFIX, 1); // Fix the scale
    }
    else
    {
        //--- Disable fixed scaling and return to auto
        ObjectSetString(0, g_button_name, OBJPROP_TEXT, g_button_text_off);
        ObjectSetInteger(0, g_button_name, OBJPROP_BGCOLOR, clrLightGray);
        ObjectSetInteger(0, g_button_name, OBJPROP_STATE, false);
        ChartSetInteger(0, CHART_SCALEFIX, 0); // Unfix the scale
    }
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Handles the logic for vertical scaling via mouse drag.           |
//+------------------------------------------------------------------+
void HandleMouseDrag(bool is_left_button_down, int current_y)
{
    //--- Start of a drag action
    if(is_left_button_down && !g_is_dragging)
    {
        g_is_dragging = true;
        g_last_mouse_y = current_y; // Set the initial Y position
        return; // Exit for now, wait for the next move event
    }
    
    //--- End of a drag action
    if(!is_left_button_down && g_is_dragging)
    {
        g_is_dragging = false;
        return;
    }
    
    //--- During a drag action
    if(is_left_button_down && g_is_dragging)
    {
        //--- Get current chart properties
        long chart_height_pixels;
        ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chart_height_pixels);
        
        // Avoid division by zero if chart height is not available
        if(chart_height_pixels <= 0) return;

        double chart_max = ChartGetDouble(0, CHART_FIXED_MAX);
        double chart_min = ChartGetDouble(0, CHART_FIXED_MIN);


        //--- Calculate how much the mouse has moved vertically
        int y_diff = current_y - g_last_mouse_y;
        
        //--- Calculate the price change per pixel
        double price_per_pixel = (chart_max - chart_min) / chart_height_pixels;
        
        //--- Calculate the total price change based on mouse movement
        double price_change = y_diff * price_per_pixel;
        
        //--- Update the fixed min and max for the chart
        ChartSetDouble(0, CHART_FIXED_MAX, chart_max + price_change);
        ChartSetDouble(0, CHART_FIXED_MIN, chart_min + price_change);
        
        //--- Update the last mouse position for the next calculation
        g_last_mouse_y = current_y;
        
        //--- Redraw the chart to show the new scale
        ChartRedraw();
    }
}
//+------------------------------------------------------------------+
