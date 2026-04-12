## AXI Read Previous Module (`axi_read_prev`)

The **AXI Read Previous** module acts as an AXI4 Master. It is responsible for reading the previous frame's image data from main memory via the Smart Connect and writing it into a local FIFO. It utilizes a Finite State Machine (FSM) and internal counters to manage AXI burst transactions based on the requested layer dimensions.

---

### **Interface Definition**

The module communicates across three primary interfaces: the Address Calculation Unit (ACU), the target FIFO (Previous FIFO), and the AXI4 Smart Connect.

| Interface | Direction | Signal Name | Description |
| :--- | :--- | :--- | :--- |
| **ACU** | Input | `prev_addr` | Base address for the previous frame to start reading from. |
| | Input | `curr_layer` | The active resolution layer determining the total data size. |
| | Input | `start_read` | Trigger pulse to begin the read transaction. |
| | Output | `read_done` | High pulse indicating the entire layer has been successfully read. |
| **Previous FIFO** | Input | `fifo_full` | Indicates the FIFO is full; used to pause AXI data reception. |
| | Output | `fifo_data` | The image data retrieved from memory, driven to the FIFO. |
| | Output | `fifo_en` | Write enable pulse to push `fifo_data` into the FIFO. |
| **Smart Connect** | In/Out | `AXI4_AR_Bus` | Full AXI4 Read Address channel signals (ARADDR, ARVALID, ARREADY, etc.). |
| | In/Out | `AXI4_R_Bus` | Full AXI4 Read Data channel signals (RDATA, RVALID, RREADY, RLAST, etc.). |

---

### **Operational Procedure (FSM)**

The module's behavior is governed by a 4-state FSM. It utilizes internal counters to track the amount of data read versus the total data required for the `prev_layer`.

#### **1. IDLE**
* **Trigger:** Waits for the `start_read` pulse from the ACU.
* **Action:** Upon receiving the pulse, it latches the incoming configurations (`prev_addr` and `curr_layer`). It initializes the internal counters and calculates the initial AXI burst size and specific address boundaries.
* **Next State:** Transitions to `WRITE_ADDR`.

#### **2. WRITE_ADDR (Issue Read Address)**
* **Action:** Uses the calculated configuration to drive the read address request onto the AXI4 AR (Address Read) channel.
* **Wait Condition:** Holds the request until the Smart Connect asserts the AXI ready signal (`ARREADY`).
* **Next State:** Once the address handshake is complete, transitions to `READ_DATA`.

#### **3. READ_DATA (Receive Burst)**
* **Action:** Monitors the `fifo_full` flag. If the FIFO has space, the module asserts the AXI ready signal (`RREADY`) to accept data.
* **Data Flow:** Incoming data (`RDATA`) is routed to `fifo_data` alongside a `fifo_en` pulse.
* **Wait Condition:** Continues receiving data until the AXI target signals the end of the burst (`RLAST`).
* **Next State:** Upon receiving the last burst beat, transitions to `CHECK_FINISH`.

#### **4. CHECK_FINISH**
* **Action:** Compares the amount of data successfully transferred against the total required size of the original frame/current layer. 
* **Next State:** * **If more data is needed:** Recalculates the remaining data, updates the `prev_addr` for the next transaction, sets the next burst size, and loops back to `WRITE_ADDR`.
  * **If all data is read:** Asserts the `read_done` pulse to notify the ACU and returns to the `IDLE` state.