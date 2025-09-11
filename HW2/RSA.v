module RSA (
    input           clk,
    input           rst_n,
    input           i_valid,
    output          ack,
    input   [15:0]  Mi,
    output          o_valid,
    output  [15:0]  Mo
);
// DO NOT MODIFY THE CODE ABOVE!!

parameter S_IDLE    = 3'd0;
parameter S_DELAY   = 3'd1;
parameter S_READ    = 3'd2;
parameter S_MP      = 3'd3;
parameter S_DECRYPT = 3'd4;
parameter S_PROC    = 3'd5;
parameter S_ENCRYPT = 3'd6;
parameter S_DONE    = 3'd7;

parameter N         = 16'd52961;
parameter kd        = 4'd11;

reg         [2:0]       state_r, state_w;
reg         [3:0]       counter;
reg         [7:0]       ke;
reg         [15:0]      t, m;
reg  signed [12:0]      Register;
reg                     set, enc;
reg         [15:0]      mp_in;
wire                    mp_start, mp_fin;
wire        [15:0]      mp_result;
reg                     ma0_start, ma1_start;
wire                    ma0_fin, ma1_fin;
wire        [15:0]      ma0_result, ma1_result;
wire signed [11:0]      add_sub_result;

assign ack = (state_w == S_READ && i_valid);
assign mp_start = (state_w == S_MP && ((state_r == S_READ) || (state_r == S_DELAY && enc)));
assign add_sub_result = (m[12]) ? (Register + m[9:0]) : (Register - m[9:0]);
assign o_valid = (state_r == S_DONE);
assign Mo = m;

Modulo_Product MP (.clk(clk), .rst_n(rst_n), .i_valid(mp_start), .b(mp_in), .o_valid(mp_fin), .result(mp_result));
Montgomery_Algorithm MA0 (.clk(clk), .rst_n(rst_n), .i_valid(ma0_start), .a(m), .b(t), .o_valid(ma0_fin), .result(ma0_result));
Montgomery_Algorithm MA1 (.clk(clk), .rst_n(rst_n), .i_valid(ma1_start), .a(t), .b(t), .o_valid(ma1_fin), .result(ma1_result));

//================================================
//                      FSM
//================================================
always @(*) begin
    case(state_r)
        S_IDLE:     state_w = S_DELAY;
        S_DELAY:    state_w = (enc) ? S_MP : (i_valid) ? S_READ : S_DELAY;
        S_READ:     state_w = S_MP;
        S_MP:       state_w = (mp_fin) ? (enc) ? S_ENCRYPT : S_DECRYPT : S_MP;
        S_DECRYPT:  state_w = (counter == 4'd3 && ma1_fin) ? S_PROC : S_DECRYPT;
        S_PROC:     state_w = S_DELAY;
        S_ENCRYPT:  state_w = (counter == 4'd7 && ma1_fin) ? S_DONE : S_ENCRYPT;
        S_DONE:     state_w = S_DELAY;
        default:    state_w = state_r;
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_r <= S_IDLE;
    else state_r <= state_w;
end

//================================================
//                DECRYPT/ENCRYPT
//================================================
always@ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m <= 16'd0;
        t <= 16'd0;
    end
    else if (state_w == S_READ && i_valid) begin
        mp_in <= Mi;
        m <= 16'd0;
        t <= 16'd0;
    end
    else if (state_r == S_PROC && state_w == S_DELAY) begin
        mp_in <= Register;
        m <= (enc)? 16'd0 : m;
        t <= (enc)? 16'd0 : t;
    end
    else if (state_r == S_MP && mp_fin) begin
        m <= 16'd1;
        t <= mp_result;
    end
    else if (state_r == S_DECRYPT || state_r == S_ENCRYPT) begin
        m <= (ma0_fin) ? ma0_result : m;
        t <= (ma1_fin) ? ma1_result : t;
    end
    else begin
        m <= m;
        t <= t;
    end
end

//================================================
//                    counter
//================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) counter <= 4'd0;
    else if (state_r == S_DECRYPT || state_r == S_ENCRYPT) begin
        counter <= (ma1_fin) ? counter + 1 : counter;
    end
    else if (state_r == S_MP && mp_fin) counter <= 4'd0;
    else counter <= counter;
end

//================================================
//                    MA0/MA1 start
//================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ma0_start <= 0;
        ma1_start <= 0;
    end
    else if (state_r == S_MP && mp_fin) begin
        ma0_start <= (enc) ? ke[0] : kd[0];
        ma1_start <= 1;
    end
    else if (state_r == S_DECRYPT) begin
        ma0_start <= (kd[counter + 1] && ma1_fin && state_w == S_DECRYPT)?  1 : 0;
        ma1_start <= (ma1_fin && state_w == S_DECRYPT)? 1 : 0;
    end
    else if (state_r == S_ENCRYPT) begin
        ma0_start <= (ke[counter + 1] && ma1_fin && state_w == S_ENCRYPT)?  1 : 0;
        ma1_start <= (ma1_fin && state_w == S_ENCRYPT)? 1 : 0;
    end
    else begin
        ma0_start <= 0;
        ma1_start <= 0;
    end
end

//================================================
//                    PROC
//================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Register <= 12'd0;
        set <= 0;
        ke <= 8'd0;
        enc <= 0;
    end
    else if (state_r == S_PROC) begin
        if (set) begin
            Register <= m;
            set <= 0;
            ke <= ke;
            enc <= enc;
        end
        else begin
            case(m[15:10])
                6'b000001: Register <= 12'd0;
                6'b000010: set <= 1;
                6'b000100: Register <= (add_sub_result[11] && !Register[11]) ? 12'h7ff : add_sub_result;
                6'b001000: Register <= (!add_sub_result[11] && Register[11]) ? 12'h800 : add_sub_result;
                6'b010000: ke <= m[7:0];
                6'b100000: enc <= 1;
                default: begin
                    Register <= Register;
                    set <= set;
                    ke <= ke;
                    enc <= enc;
                end
            endcase
        end
    end
    else begin
        Register <= Register;
        set <= set;
        ke <= ke;
        enc <= (state_r == S_DONE) ? 0 : enc;
    end
end
endmodule

//================================================
//                Modulo_Product
//================================================
module Modulo_Product (
    input           clk,
    input           rst_n,
    input           i_valid,
    input   [15:0]  b,
    output          o_valid,
    output  [15:0]  result
);

parameter S_IDLE    = 2'd0;
parameter S_PROC    = 2'd1;
parameter S_DONE    = 2'd2;
parameter N         = 16'd52961;

reg [2:0] state_r, state_w;
reg [4:0] counter;
reg [15:0] m, t;

assign o_valid = (state_r == S_DONE);
assign result = m;

always @(*) begin
    case(state_r)
        S_IDLE:     state_w = (i_valid) ? S_PROC : S_IDLE;
        S_PROC:     state_w = (counter == 5'd16) ? S_DONE : S_PROC;
        S_DONE:     state_w = S_IDLE;
        default:    state_w = state_r;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_r <= S_IDLE;
    else state_r <= state_w;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m <= 16'd0;
        t <= 16'd0;
        counter <= 5'd0;
    end
    else if (state_r == S_PROC) begin
        if (counter == 5'd16) m <= (m + t >= N) ? m + t - N : m + t;
        else m <= m;
        t <= ({t, 1'b0} >= N) ? {t, 1'b0} - N : {t, 1'b0};
        counter <= counter + 1;
    end
    else begin
        m <= (i_valid) ? 16'd0 : m;
        t <= (i_valid) ? b : t;
        counter <= (i_valid) ? 5'd0 : counter;
    end
end
endmodule

//================================================
//                Montgomery_Algorithm
//================================================
module Montgomery_Algorithm (
    input           clk,
    input           rst_n,
    input           i_valid,
    input   [15:0]  a,
    input   [15:0]  b,
    output          o_valid,
    output  [15:0]  result
);

parameter S_IDLE    = 2'd0;
parameter S_PROC    = 2'd1;
parameter S_DONE    = 2'd2;
parameter N         = 16'd52961;

reg [1:0] state_r, state_w;
reg [3:0] counter;
reg [17:0] m;
wire [17:0] tmp;

assign tmp = m + b;
assign o_valid = (state_r == S_DONE);
assign result = (m >= N) ? m - N : m;

always @(*) begin
    case(state_r)
        S_IDLE:     state_w = (i_valid) ? S_PROC : S_IDLE;
        S_PROC:     state_w = (counter == 4'd15) ? S_DONE : S_PROC;
        S_DONE:     state_w = S_IDLE;
        default:    state_w = state_r;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_r <= S_IDLE;
    else state_r <= state_w;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 4'd0;
        m <= 18'd0;
    end
    else if (state_r == S_PROC) begin
        if (a[counter]) m <= (tmp[0]) ? (tmp + N) >> 1 : tmp >> 1;
        else m <= (m[0]) ? (m + N) >> 1 : m >> 1;
        counter <= counter + 1;
    end
    else begin
        m <= (i_valid) ? 18'd0 : m;
        counter <= (i_valid) ? 4'd0 : counter;
    end
end
endmodule