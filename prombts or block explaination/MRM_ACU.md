## Memory Read Address Calculation Unit (ACU)

The **Memory Read ACU** is responsible for generating the precise physical memory addresses for the current frame, previous frame, and optical flow data. It utilizes a hierarchical offset system based on the current processing layer (original frame vs. downsampled thumbnails).

---

### **Interface Definition**

| Type | Signal Name | Description |
| :--- | :--- | :--- |
| **Inputs** | `curr_frame_idx` | Index of the current frame in memory. |
| | `prev_frame_idx` | Index of the previous frame in memory. |
| | `current_layer` | The active resolution layer (e.g., Layer 0 = Original). |
| | `mem_read_start` | Trigger pulse to initiate address calculation and output. |
| **Outputs** | `curr_frame_addr` | Calculated base address for the current frame layer. |
| | `prev_frame_addr` | Calculated base address for the previous frame layer. |
| | `flow_addr` | Calculated address for the optical flow data. |
| | `flow_enable` | Active high signal (disabled only for Layer 4). |
| | `start_read` | Output pulse indicating addresses are valid and ready. |
| | `current_layer` | Registered version of the input layer. |

---

### **Address Calculation Logic**

The module calculates addresses by adding a layer-specific **offset** to the frame's **base address**. These offsets are pre-calculated and stored as local parameters based on frame dimensions ($W \times H$).

#### **1. Frame Addresses**
The address for both current and previous frames follows this derivation:
$$\text{Address} = \text{Base Address} + \text{Layer Offset}$$

* **Layer 0 (Original):** $\text{Offset} = 0$
* **Layer 1:** $\text{Offset} = W \times H$
* **Layer 2:** $\text{Offset} = (W \times H) + (W \times H \gg 2)$
* **Layer 3+:** Follows the cumulative sum of all previous thumbnail sizes.

#### **2. Flow Address**
The `flow_address` points to the memory region following all frame data (original + all thumbnails).
$$\text{Flow Address} = \text{Base Address} + \sum \text{All Layer Sizes}$$

#### **3. Flow Enable Logic**
The flow data is only valid for the primary layers.
* **If** `current_layer == 4`: `flow_enable = 0`
* **Else**: `flow_enable = 1`

---

### **Operational Procedure**

1.  **Idle State:** The module waits for the `mem_read_start` pulse.
2.  **Trigger:** Upon receiving the pulse, the ACU latches the `curr_frame_idx`, `prev_frame_idx`, and `current_layer`.
3.  **Processing:**
    * Retrieves pre-stored offsets for the selected `current_layer`.
    * Computes `curr_frame_addr`, `prev_frame_addr`, and `flow_addr`.
    * Determines `flow_enable` status.
4.  **Output:** The module drives the calculated addresses and the registered `current_layer` to the bus, accompanied by a `start_read` pulse to notify downstream components.