
-- Asynchronous Input Synchronization
--
-- The following code is an example of synchronizing an asynchronous input
-- of a design to reduce the probability of metastability affecting a circuit.
--
-- The following synthesis and implementation attributes are added to the code
-- in order improve the MTBF characteristics of the implementation:
--
--  ASYNC_REG="TRUE" - Specifies registers will be receiving asynchronous data
--                     input to allow tools to report and improve metastability
--
-- The following constants are available for customization:
--
--   SYNC_STAGES     - Integer value for number of synchronizing registers, must be 2 or higher
--   PIPELINE_STAGES - Integer value for number of registers on the output of the
--                     synchronizer for the purpose of improveing performance.
--                     Particularly useful for high-fanout nets.
--   INIT            - Initial value of synchronizer registers upon startup, 1'b0 or 1'b1.

library ieee;
use ieee.std_logic_1164.all;
entity async_input_sync is generic (
                                    SYNC_STAGES : integer := 3;
                                    PIPELINE_STAGES : integer := 1;
                                    INIT : std_logic := '0'
                                   );
                            port   (
                                    clk : in std_logic;
                                    async_in : in std_logic;
                                    sync_out : out std_logic
                                   );
end async_input_sync;

architecture rtl of async_input_sync is
signal sreg : std_logic_vector(SYNC_STAGES-1 downto 0) := (others => INIT);
attribute async_reg : string;
attribute async_reg of sreg : signal is "true";
signal sreg_pipe : std_logic_vector(PIPELINE_STAGES-1 downto 0) := (others => INIT);
attribute shreg_extract : string;
attribute shreg_extract of sreg_pipe : signal is "false";
begin
   process(clk)
   begin
    if(clk'event and clk='1')then
       sreg <= sreg(SYNC_STAGES-2 downto 0) & async_in;  -- Async Input async_in
    end if;
   end process;

   no_pipeline : if PIPELINE_STAGES = 0 generate
   begin
      sync_out <= sreg(SYNC_STAGES-1);
   end generate;

   one_pipeline : if PIPELINE_STAGES = 1 generate
   begin
    process(clk)
    begin
      if(clk'event and clk='1') then
        sync_out <= sreg(SYNC_STAGES-1);
      end if;
    end process;
   end generate;

   multiple_pipeline : if PIPELINE_STAGES > 1 generate
   begin
    process(clk)
    begin
      if(clk'event and clk='1') then
        sreg_pipe <= sreg_pipe(PIPELINE_STAGES-2 downto 0) & sreg(SYNC_STAGES-1);
      end if;
    end process;
    sync_out <= sreg_pipe(PIPELINE_STAGES-1);
   end generate;
end rtl;
-- The following is an instantiation template for async_input_sync
-- Component Declaration
-- Uncomment the below component declaration when using
-- component async_input_sync
-- generic (
--          SYNC_STAGES : integer := 3;
--          PIPELINE_STAGES : integer := 1;
--          INIT : std_logic := '0'
--          );
-- port   (
--          clk : in std_logic;
--          async_in : in std_logic;
--          sync_out : out std_logic
--        );
--end component;

-- Instantiation
-- Uncomment the instantiation below when using
--<your_instance_name> : async_input_sync
--
-- generic map (
--          SYNC_STAGES => 3,
--          PIPELINE_STAGES => 1,
--          INIT => '0'
--          );
-- port map (
--          clk => clk,
--          async_in => async_in,
--          sync_out => sync_out
--        );