`default_nettype none

module video_sig_gen #(parameter ACTIVE_H_PIXELS = 1280,
                       parameter H_FRONT_PORCH = 110,
                       parameter H_SYNC_WIDTH = 40,
                       parameter H_BACK_PORCH = 220,
                       parameter ACTIVE_LINES = 720,
                       parameter V_FRONT_PORCH = 5,
                       parameter V_SYNC_WIDTH = 5,
                       parameter V_BACK_PORCH = 20,
                       parameter FPS = 60)
                      (input wire pixel_clk_in,
                       input wire rst_in,
                        output logic [$clog2(TOTAL_PIXELS)-1:0] hcount_out, 
                        output logic [$clog2(TOTAL_LINES)-1:0] vcount_out, 
                        output logic vs_out, 
                        output logic hs_out, 
                        output logic ad_out,
                        output logic nf_out, 
                        output logic [5:0] fc_out); //frame
    
    localparam TOTAL_PIXELS = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH;
    localparam TOTAL_LINES  = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH;

    localparam HSYNC_START = ACTIVE_H_PIXELS + H_FRONT_PORCH;
    localparam HSYNC_STOP = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH;
    localparam VSYNC_START = ACTIVE_LINES + V_FRONT_PORCH;
    localparam VSYNC_STOP = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH;
    
    always_ff @(posedge pixel_clk_in) begin
        if (rst_in) begin
            hcount_out <= 'b0;
            vcount_out <= 'b0;
            vs_out <= 'b0;
            hs_out <= 'b0;
            ad_out <= 'b0;
            nf_out <= 'b0;
            fc_out <= 'b0;
        end else begin
            hcount_out <= (hcount_out == TOTAL_PIXELS-1)? 0 : hcount_out + 'b1;
            vcount_out <= (hcount_out < TOTAL_PIXELS-1)? vcount_out 
                                : (vcount_out == TOTAL_LINES-1)? 0 : vcount_out + 'b1;
            hs_out <= ((HSYNC_START <= hcount_out) && (hcount_out < HSYNC_STOP))? 1 : 0;
            vs_out <= ((VSYNC_START <= vcount_out) && (vcount_out < VSYNC_STOP))? 1 : 0;
            ad_out <= ((hcount_out < ACTIVE_H_PIXELS) && (vcount_out < ACTIVE_LINES));
            nf_out <= ((hcount_out == TOTAL_PIXELS-1) && (vcount_out == TOTAL_LINES-1));
            fc_out <= (hcount_out < TOTAL_PIXELS-1 || vcount_out < TOTAL_LINES-1)? fc_out 
                            : (fc_out == FPS-1)? 0 : fc_out + 'b1;
        end
    end
    
endmodule
    
`default_nettype wire
