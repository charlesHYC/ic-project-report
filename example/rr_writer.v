// rr_writer - a tiny round-robin channel writer, used only as a self-contained
// demo for the ic-project-report skill: something to simulate and photograph.
module rr_writer #(
    parameter CH      = 4,          // number of downstream channels
    parameter DW      = 32,
    parameter AW      = 16,
    parameter BEATS   = 4           // beats per burst
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                go,
    input  wire [15:0]         n_burst,
    output reg                 busy,
    output reg                 done,
    output reg  [31:0]         cycles,      // hardware stopwatch
    output reg  [CH-1:0]       awvalid,
    output reg  [CH*AW-1:0]    awaddr,
    output reg  [CH-1:0]       wvalid,
    output reg  [CH*DW-1:0]    wdata,
    output reg  [CH-1:0]       wlast
);
    localparam S_IDLE = 2'd0, S_AW = 2'd1, S_W = 2'd2, S_NEXT = 2'd3;
    reg [1:0]  state;
    reg [15:0] burst;               // which burst we are on
    reg [3:0]  beat;
    integer    i;

    // burst N goes to channel N mod CH, and the address inside that channel
    // only advances once the walk has been all the way round.
    wire [$clog2(CH)-1:0] ch   = burst[$clog2(CH)-1:0];
    wire [AW-1:0]         addr = (burst / CH) * (BEATS * (DW/8));

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; busy <= 0; done <= 0; cycles <= 0;
            burst <= 0; beat <= 0; awvalid <= 0; wvalid <= 0; wlast <= 0;
        end else begin
            done <= 0;
            if (busy) cycles <= cycles + 1;
            case (state)
            S_IDLE: if (go) begin
                        busy <= 1; cycles <= 0; burst <= 0; state <= S_AW;
                    end
            S_AW:   begin
                        awvalid <= 0; awvalid[ch] <= 1;
                        awaddr  <= 0; awaddr[ch*AW +: AW] <= addr;
                        beat    <= 0; state <= S_W;
                    end
            S_W:    begin
                        awvalid <= 0;
                        wvalid  <= 0; wvalid[ch] <= 1;
                        wdata   <= 0; wdata[ch*DW +: DW] <= {burst, 12'h0, beat};
                        wlast   <= 0; wlast[ch] <= (beat == BEATS-1);
                        if (beat == BEATS-1) state <= S_NEXT;
                        beat <= beat + 1;
                    end
            S_NEXT: begin
                        wvalid <= 0; wlast <= 0;
                        if (burst + 1 == n_burst) begin
                            busy <= 0; done <= 1; state <= S_IDLE;
                        end else begin
                            burst <= burst + 1; state <= S_AW;
                        end
                    end
            endcase
        end
    end
endmodule
