class zoom_transaction;
    // Parameters matching the top module
    parameter IMG_WIDTH  = 1280;
    parameter IMG_HEIGHT = 720;

    // Random Variables
    rand bit [2:0]  curr_layer;
    rand logic [31:0] flow_data_arr[$];

    // Constraints
    constraint c_layer_valid {
        curr_layer inside {[0:3]};
    }

    constraint c_flow_data_bits {
        foreach (flow_data_arr[i]) {
            flow_data_arr[i][31:29] == 3'd0;
            flow_data_arr[i][15:12] == 3'd0;
        }
    }

    constraint c_flow_data_size {
        // Size must exactly match the number of pixels in the layer
        flow_data_arr.size() == ((IMG_WIDTH / 2) >> curr_layer) * ((IMG_HEIGHT / 2) >> curr_layer);
    }

    // Functional Coverage Group
    covergroup cg_layer;
        option.per_instance = 1;
        cp_layer: coverpoint curr_layer {
            bins layer_0 = {0};
            bins layer_1 = {1};
            bins layer_2 = {2};
            bins layer_3 = {3};
            bins layer_4 = {4};
        }
    endgroup

    // Constructor
    function new();
        cg_layer = new();
    endfunction

    // Coverage Sampling
    function void sample_cov();
        cg_layer.sample();
    endfunction

endclass