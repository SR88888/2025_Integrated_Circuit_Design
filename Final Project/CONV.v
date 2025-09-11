module  CONV(
	input				clk,
	input				rst_n,
	input 				mode,
	input       		in_valid,
	output reg			out_valid,
	output 		[13:0] 	AWADDR,
	output		 [7:0] 	AWLEN,
	output 				AWVALID,
	input 				AWREADY,
	output reg  [31:0]	WDATA,
	output 				WVALID,
	input 				WREADY,
	output 		[13:0] 	ARADDR,
	output 		 [7:0] 	ARLEN,
	output 				ARVALID,
	input 				ARREADY,
	input		[31:0] 	RDATA,
	input 				RVALID,
	output reg			RREADY
);
//======================================
localparam WEIGHT1 	= 20'hABC2E;
localparam WEIGHT2 	= 20'hB52E2;
localparam WEIGHT3 	= 20'hAF5C4;
localparam WEIGHT4 	= 20'hE5518;
localparam WEIGHT5 	= 20'h71650;
localparam WEIGHT6 	= 20'hA938B;
localparam WEIGHT7 	= 20'h5251F;
localparam WEIGHT8 	= 20'h7DFC0;
localparam WEIGHT9 	= 20'hEB885;
localparam BIAS 	= 16'h1310;
//======================================
localparam IDLE 	= 4'd0;
localparam CONV_K1 	= 4'd1;
localparam CONV_K2 	= 4'd2;
localparam CONV_K3 	= 4'd3;
localparam CONV_K4 	= 4'd4;
localparam CONV_K5 	= 4'd5;
localparam CONV_K6 	= 4'd6;
localparam CONV_K7 	= 4'd7;
localparam CONV_K8 	= 4'd8;
localparam CONV_K9 	= 4'd9;
localparam RELU 	= 4'd10;
localparam MUL 		= 4'd11;
localparam READ 	= 4'd12;
localparam WRITE_L0 = 4'd13;
localparam POOL 	= 4'd14;
localparam WRITE_L1 = 4'd15;
//======================================
reg  		 [3:0] 	state_r, state_w, state_tmp;
reg  		 [5:0]	cnt_x, cnt_y;
reg					mode_;
wire 			 	is_up, is_down, is_left, is_right;
wire 				skip_mul;
wire 		[11:0] 	P1, P2, P3, P4, P5, P6, P7, P8, P9;
wire 		[15:0]  data_in;
wire 		[19:0] 	weight;
reg  signed	[35:0] 	product;
reg 				mul_fin;
reg  signed [36:0]	conv_result;
wire 		[31:0]	relu_result;
reg 		[31:0] 	max_pool_result;
wire 				update_mp_result;
//======================================
assign is_up 	= (cnt_y == 6'd0  || (cnt_y == 6'd1  && mode_));
assign is_down 	= (cnt_y == 6'd63 || (cnt_y == 6'd62 && mode_));
assign is_left 	= (cnt_x == 6'd0  || (cnt_x == 6'd1  && mode_));
assign is_right = (cnt_x == 6'd63 || (cnt_x == 6'd62 && mode_));
assign skip_mul   = (state_tmp == CONV_K1 && (is_up || is_left)) 	||
					(state_tmp == CONV_K2 && (is_up))				||
					(state_tmp == CONV_K3 && (is_up || is_right)) 	||
					(state_tmp == CONV_K4 && (is_left))				||
					(state_tmp == CONV_K6 && (is_right)) 			||
					(state_tmp == CONV_K7 && (is_down || is_left)) 	||
					(state_tmp == CONV_K8 && (is_down)) 			||
					(state_tmp == CONV_K9 && (is_down || is_right));
assign P1 = (mode_ == 1'b0) ? {cnt_y, cnt_x} - 7'd65 : {cnt_y, cnt_x} - 8'd130;
assign P2 = (mode_ == 1'b0) ? {cnt_y, cnt_x} - 7'd64 : {cnt_y, cnt_x} - 8'd128;
assign P3 = (mode_ == 1'b0) ? {cnt_y, cnt_x} - 6'd63 : {cnt_y, cnt_x} - 7'd126;
assign P4 = (mode_ == 1'b0) ? {cnt_y, cnt_x} - 1'd1  : {cnt_y, cnt_x} - 2'd2  ;
assign P5 = (mode_ == 1'b0) ? {cnt_y, cnt_x}		 : {cnt_y, cnt_x}         ;
assign P6 = (mode_ == 1'b0) ? {cnt_y, cnt_x} + 1'd1	 : {cnt_y, cnt_x} + 2'd2  ;
assign P7 = (mode_ == 1'b0) ? {cnt_y, cnt_x} + 6'd63 : {cnt_y, cnt_x} + 7'd126;
assign P8 = (mode_ == 1'b0) ? {cnt_y, cnt_x} + 7'd64 : {cnt_y, cnt_x} + 8'd128;
assign P9 = (mode_ == 1'b0) ? {cnt_y, cnt_x} + 7'd65 : {cnt_y, cnt_x} + 8'd130;
assign data_in = RDATA[31:16];
assign weight = (state_tmp == CONV_K1) ? WEIGHT1 :
				(state_tmp == CONV_K2) ? WEIGHT2 :
				(state_tmp == CONV_K3) ? WEIGHT3 :
				(state_tmp == CONV_K4) ? WEIGHT4 :
				(state_tmp == CONV_K5) ? WEIGHT5 :
				(state_tmp == CONV_K6) ? WEIGHT6 :
				(state_tmp == CONV_K7) ? WEIGHT7 :
				(state_tmp == CONV_K8) ? WEIGHT8 :
				(state_tmp == CONV_K9) ? WEIGHT9 : 20'd0;
assign ARADDR = (state_tmp == CONV_K1) ? P1 :
				(state_tmp == CONV_K2) ? P2 :
				(state_tmp == CONV_K3) ? P3 :
				(state_tmp == CONV_K4) ? P4 :
				(state_tmp == CONV_K5) ? P5 :
				(state_tmp == CONV_K6) ? P6 :
				(state_tmp == CONV_K7) ? P7 :
				(state_tmp == CONV_K8) ? P8 :
				(state_tmp == CONV_K9) ? P9 : 14'd0;
assign ARLEN = 8'd0;
assign ARVALID = (state_r == READ) && (~skip_mul) && (state_tmp != RELU);
assign AWADDR = (state_r == POOL) ? {4'b1000, cnt_y[5:1], cnt_x[5:1]} : {1'b1, cnt_y, cnt_x};
assign AWLEN = 8'd0;
assign AWVALID = (state_r == RELU || state_r == POOL);
assign WVALID = (state_r == WRITE_L0 || state_r == WRITE_L1);
assign relu_result = (conv_result[36]) ? 32'd0 : conv_result[31:0];
assign update_mp_result = ((WDATA > max_pool_result) && WVALID);
//======================================
// FSM
//======================================
always @(*) begin
	case(state_r) // synopsys parallel_case
		IDLE: 		state_w = (in_valid) ? READ : IDLE;
		READ: 		state_w = (ARREADY && ~skip_mul) ? state_tmp : READ;
		CONV_K1: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K1); 
		CONV_K2: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K2);
		CONV_K3: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K3);
		CONV_K4: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K4);
		CONV_K5: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K5);
		CONV_K6: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K6);
		CONV_K7: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K7);
		CONV_K8: 	state_w = (skip_mul) ? READ : ((RVALID) ? MUL : CONV_K8);
		CONV_K9: 	state_w = (skip_mul) ? RELU : ((RVALID) ? MUL : CONV_K9);
		MUL: 		state_w = (state_tmp == CONV_K9) ? RELU : READ;
		RELU: 		state_w = (AWREADY) ? WRITE_L0 : RELU;
		WRITE_L0: 	state_w = (WREADY) ? ((cnt_x[0] && cnt_y[0]) ? POOL : READ) : WRITE_L0;
		POOL: 		state_w = (AWREADY) ? WRITE_L1 : POOL;
		WRITE_L1: 	state_w = (WREADY) ? ((cnt_x[5:1] == 5'd31 && cnt_y[5:1] == 5'd31) ? IDLE : READ) : WRITE_L1;
	endcase
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)	state_r <= IDLE;
	else 		state_r <= state_w;
end
//======================================
// state_tmp
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)								state_tmp <= CONV_K1;
	else if (state_r == RELU)				state_tmp <= CONV_K1;
	else if (state_r == MUL) 				state_tmp <= state_tmp + 4'd1;
	else if (state_r == READ && skip_mul) 	state_tmp <= state_tmp + 4'd1;
end
//======================================
// cnt
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)	begin
		cnt_x <= 6'd0;
		cnt_y <= 6'd0;
	end
	else if (state_r == WRITE_L0 && WREADY) begin
		cnt_x <= {cnt_x[5:1], cnt_x[0] + 1'd1};
		cnt_y <= (cnt_x[0]) ? {cnt_y[5:1], cnt_y[0] + 1'd1} : cnt_y;
	end
	else if (state_r == WRITE_L1 && WREADY) begin
		cnt_x <= {cnt_x[5:1] + 5'd1, cnt_x[0]};
		cnt_y <= (cnt_x[5:1] == 5'd31) ? {cnt_y[5:1] + 1'd1, cnt_y[0]} : cnt_y;
	end
end
//======================================
// RREADY
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)			RREADY <= 1'b0;
	else if (ARVALID)	RREADY <= 1'b1;
	else if (RVALID) 	RREADY <= 1'b0;
end
//======================================
// product
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)					product <= 36'd0;
	else if (state_w == MUL)	product <= $signed(data_in) * $signed(weight);
end
//======================================
// mul_fin
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)					mul_fin <= 1'b0;
	else if (state_w == MUL) 	mul_fin <= 1'b1;
	else 						mul_fin <= 1'b0;
end
//======================================
// conv_result
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)					conv_result <= BIAS;
	else if (WVALID && WREADY) 	conv_result <= BIAS;
	else if (mul_fin) 			conv_result <= conv_result + product;
end
//======================================
// max_pool_result
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)								max_pool_result <= 32'd0;
	else if (state_r == WRITE_L1 && WREADY) max_pool_result <= 32'd0;
	else if (update_mp_result) 				max_pool_result <= WDATA;
end
//======================================
// WDATA
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)						WDATA <= 32'd0;
	else if (state_w == WRITE_L0)	WDATA <= relu_result;
	else if (state_w == WRITE_L1)	WDATA <= max_pool_result;
	else 							WDATA <= WDATA;
end
//======================================
// out_valid
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)							out_valid <= 1'b0;
	else if (WREADY && state_w == IDLE) out_valid <= 1'b1;
	else 								out_valid <= 1'b0;
end
//======================================
// mode
//======================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)			mode_ <= 1'b0;
	else if (in_valid) 	mode_ <= mode;
	else 				mode_ <= mode_;
end
//======================================
endmodule