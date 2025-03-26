library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FIR_Filter is
    Generic (
        filter_taps  : integer := 50;
        input_width  : integer range 8 to 25 := 24; 
        coeff_width  : integer range 8 to 18 := 16;
        output_width : integer range 8 to 43 := 43  
    );
    Port ( 
           clk    : in STD_LOGIC;
           reset  : in STD_LOGIC;
           enable : in STD_LOGIC;
           switch : in STD_LOGIC_VECTOR (2 downto 0); -- 3-bit switch sinyali
           data_i : in STD_LOGIC_VECTOR (input_width-1 downto 0);
           data_o : out STD_LOGIC_VECTOR (output_width-1 downto 0)
           );
end FIR_Filter;

architecture Behavioral of FIR_Filter is

attribute use_dsp : string;
attribute use_dsp of Behavioral : architecture is "yes";

constant mac_width : integer := coeff_width+input_width;

type input_registers is array(0 to filter_taps-1) of signed(input_width-1 downto 0);
signal areg_s  : input_registers := (others=>(others=>'0'));

type coeff_registers is array(0 to filter_taps-1) of signed(coeff_width-1 downto 0);
signal breg_s : coeff_registers := (others=>(others=>'0'));

type mult_registers is array(0 to filter_taps-1) of signed(input_width+coeff_width-1 downto 0);
signal mreg_s : mult_registers := (others=>(others=>'0'));

type dsp_registers is array(0 to filter_taps-1) of signed(mac_width-1 downto 0);
signal preg_s : dsp_registers := (others=>(others=>'0'));

signal dout_s : std_logic_vector(mac_width-1 downto 0);
signal sign_s : signed(mac_width-input_width-coeff_width+1 downto 0) := (others=>'0');

-- **Tüm katsayý setlerini içeren array**
type coefficients_array is array (0 to 7, 0 to 49) of signed(15 downto 0);
signal coeffs : coefficients_array := (
    -- **0.5 (Integrator)**
    (x"8000", x"4000", x"3000", x"2800", x"2300", x"1F80", x"1CE0", x"1AD0", x"1923", x"17BE", 
     x"168E", x"1587", x"14A2", x"13D6", x"1321", x"127E", x"11EA", x"1163", x"10E7", x"1075", 
     x"100C", x"0FAA", x"0F4F", x"0EFA", x"0EAA", x"0E5F", x"0E18", x"0DD5", x"0D96", x"0D5A", 
     x"0D21", x"0CEB", x"0CB7", x"0C86", x"0C57", x"0C2A", x"0BFF", x"0BD5", x"0BAD", x"0B87", 
     x"0B62", x"0B3E", x"0B1C", x"0AFB", x"0ADB", x"0ABC", x"0A9E", x"0A81", x"0A65", x"0A4A"),
    -- **0.6 (Integrator)**
    (x"8000", x"4CCD", x"3D71", x"353F", x"2FEC", x"2C17", x"2926", x"26CC", x"24DC", x"2338",
     x"21D0", x"2095", x"1F7F", x"1E87", x"1DA8", x"1CDD", x"1C24", x"1B7B", x"1ADF", x"1A4E",
     x"19C7", x"1949", x"18D4", x"1865", x"17FD", x"179B", x"173E", x"16E6", x"1692", x"1642",
     x"15F6", x"15AE", x"1568", x"1526", x"14E6", x"14A9", x"146E", x"1436", x"13FF", x"13CB",
     x"1398", x"1367", x"1338", x"130A", x"12DE", x"12B3", x"1289", x"1261", x"123A", x"1214"),
    -- **0.7 (Integrator)**
    (x"8000", x"599A", x"4C29", x"448B", x"3F67", x"3B99", 
     x"389E", x"3631", x"3429", x"326C", x"30E9", x"2F93", 
     x"2E63", x"2D51", x"2C58", x"2B75", x"2AA4", x"29E4", 
     x"2931", x"288B", x"27EF", x"275D", x"26D3", x"2652", 
     x"25D7", x"2563", x"24F5", x"248B", x"2427", x"23C7", 
     x"236C", x"2314", x"22C0", x"226F", x"2221", x"21D6", 
     x"218E", x"2149", x"2105", x"20C4", x"2085", x"2048", 
     x"200D", x"1FD4", x"1F9D", x"1F67", x"1F32", x"1EFF", 
     x"1ECE", x"1E9D"),
     -- **0.8 (Integrator)**
    (x"8000", x"6666", x"5C29", x"5604", x"51B7", x"4E72", 
     x"4BD5", x"49AA", x"47D3", x"463A", x"44D3", x"4392", 
     x"4272", x"416C", x"407D", x"3FA1", x"3ED5", x"3E18", 
     x"3D67", x"3CC2", x"3C26", x"3B94", x"3B09", x"3A86", 
     x"3A09", x"3992", x"3921", x"38B4", x"384D", x"37E9", 
     x"378A", x"372E", x"36D6", x"3681", x"362F", x"35DF", 
     x"3593", x"3549", x"3501", x"34BB", x"3478", x"3436", 
     x"33F7", x"33B9", x"337D", x"3342", x"3309", x"32D1", 
     x"329B", x"3266"),
    -- **0.9 (Integrator)**  
    (x"8000", x"7333", x"6D71", x"69CB", x"6726", x"6516", 
     x"6366", x"61FB", x"60C1", x"5FAE", x"5EB9", x"5DDD", 
     x"5D14", x"5C5D", x"5BB4", x"5B18", x"5A86", x"59FE", 
     x"597E", x"5905", x"5893", x"5827", x"57C1", x"575F", 
     x"5702", x"56A9", x"5653", x"5601", x"55B3", x"5567", 
     x"551E", x"54D8", x"5494", x"5452", x"5413", x"53D5", 
     x"539A", x"5360", x"5328", x"52F1", x"52BC", x"5289", 
     x"5256", x"5225", x"51F5", x"51C7", x"5199", x"516D", 
     x"5141", x"5117"),
    (
    x"7300", x"8000", x"4CCD", x"B69D", x"3C6A", x"C578", 
    x"33FC", x"CD48", x"2E99", x"D257", x"2AC2", x"D5FA", 
    x"27D5", x"D8C4", x"2581", x"DAFF", x"2398", x"DCD6", 
    x"21FB", x"DE64", x"209A", x"DFBB", x"1F66", x"E0E6", 
    x"1E56", x"E1EE", x"1D64", x"E2DA", x"1C8A", x"E3AE", 
    x"1BC5", x"E46F", x"1B11", x"E51E", x"1A6D", x"E5C0", 
    x"19D5", x"E655", x"1948", x"E6DE", x"18C6", x"E75F", 
    x"184C", x"E7D6", x"17DA", x"E846", x"176F", x"E8B0", 
    x"170A", x"E913"),
    -- **0.7 (Derivative)**      
     (
    x"6BF4", x"8000", x"599A", x"AB85", x"4A5E", x"B87D", 
    x"4244", x"BFAB", x"3CF5", x"C47B", x"3919", x"C809", 
    x"361C", x"CAD2", x"33B3", x"CD16", x"31B1", x"CEFB", 
    x"2FFC", x"D09B", x"2E81", x"D205", x"2D33", x"D344", 
    x"2C0B", x"D461", x"2B01", x"D561", x"2A10", x"D64A", 
    x"2935", x"D71F", x"286B", x"D7E2", x"27B1", x"D896", 
    x"2705", x"D93E", x"2665", x"D9DA", x"25CF", x"DA6C", 
    x"2543", x"DAF4", x"24BF", x"DB75", x"2443", x"DBEF", 
    x"23CE", x"DC62"),
    -- **0.8 (Derivative)**       
    (x"6AF6", x"8000", x"6666", x"9EB8", x"5A1D", x"A8CC", 
    x"5354", x"AEAA", x"4EC4", x"B2BD", x"4B60", x"B5D2", 
    x"48B4", x"B849", x"4683", x"BA54", x"44AA", x"BC10", 
    x"4313", x"BD90", x"41AF", x"BEE3", x"4072", x"C011", 
    x"3F57", x"C120", x"3E56", x"C217", x"3D6C", x"C2F9", 
    x"3C95", x"C3C8", x"3BCE", x"C488", x"3B16", x"C53B", 
    x"3A6A", x"C5E1", x"39CA", x"C67D", x"3933", x"C710", 
    x"38A5", x"C79A", x"381F", x"C81D", x"37A0", x"C899", 
    x"3727", x"C90F")
);

type coefficients is array (0 to 49) of signed(15 downto 0);
signal coeff_s: coefficients := (others => (others => '0')); -- Baþlangýç deðeri ekledim

signal switch_sync,switch_1,switch_2 : std_logic_vector(2 downto 0);

begin  

-- **Switch sinyaline göre katsayýlarý güncelle**
process(clk)
begin
    if rising_edge(clk) then
        switch_sync <= switch_1;
        switch_1    <= switch_2;
        switch_2    <= switch;   
    end if;
end process;

Coeff_Array_1: for i in 0 to filter_taps-1 generate
      coeff_s(i) <= coeffs(to_integer(unsigned(switch)),i); -- **Düzgün indeksleme**
end generate;


Coeff_Array: for i in 0 to filter_taps-1 generate
    Coeff: for n in 0 to coeff_width-1 generate
        Coeff_Sign: if n > coeff_width-2 generate
            breg_s(i)(n) <= coeff_s(i)(coeff_width-1);
        end generate;
        Coeff_Value: if n < coeff_width-1 generate
            breg_s(i)(n) <= coeff_s(i)(n);
        end generate;
    end generate;
end generate;

data_o <= std_logic_vector(preg_s(0)(mac_width-2 downto mac_width-output_width-1));         
      
process(clk)
begin
    if rising_edge(clk) then
        if (reset = '1') then
            for i in 0 to filter_taps-1 loop
                areg_s(i) <= (others=> '0');
                mreg_s(i) <= (others=> '0');
                preg_s(i) <= (others=> '0');
            end loop;
        elsif (reset = '0') then
            if(enable = '1') then         
                for i in 0 to filter_taps-1 loop
                    areg_s(i) <= signed(data_i);
                    if (i < filter_taps-1) then
                        mreg_s(i) <= areg_s(i) * breg_s(i);
                        preg_s(i) <= mreg_s(i) + preg_s(i+1);
                    else
                        mreg_s(i) <= areg_s(i) * breg_s(i);
                        preg_s(i) <= mreg_s(i);
                    end if;
                end loop; 
            end if;    
        end if;
    end if;
end process;

end Behavioral;
