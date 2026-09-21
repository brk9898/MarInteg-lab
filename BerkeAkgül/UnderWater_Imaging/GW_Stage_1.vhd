library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity GW_Stage_1 is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480
    );
    Port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        R_i         : in  std_logic_vector(7 downto 0);
        G_i         : in  std_logic_vector(7 downto 0);
        B_i         : in  std_logic_vector(7 downto 0);
        pixel_valid : in  std_logic;
        frame_done  : in  std_logic;
        R_avg_o     : out std_logic_vector(7 downto 0);
        G_avg_o     : out std_logic_vector(7 downto 0);
        B_avg_o     : out std_logic_vector(7 downto 0);
        Gray_avg_o  : out std_logic_vector(9 downto 0)  
    );
end GW_Stage_1;



architecture Behavioral of GW_Stage_1 is


    signal R_sum, G_sum, B_sum       : unsigned(26 downto 0) := (others => '0');    
    signal R_avg, G_avg, B_avg       : unsigned(35 downto 0) := (others => '0');
    signal Gray_sum            : unsigned(9 downto 0) := (others => '0');  
    signal Gray_avg            : unsigned(9 downto 0) := (others => '0'); 
    signal mult_result         : unsigned(24 downto 0) := (others => '0'); 


    signal stage1_valid              : std_logic := '0';
    signal stage2_valid              : std_logic := '0';
    signal stage3_valid              : std_logic := '0'; 

    
    


    constant N_PIXELS : integer := IMG_WIDTH * IMG_HEIGHT;


begin
    process(clk)
    
    begin

        if rising_edge(clk) then
            if reset = '1' then
            
                stage1_valid <= '0';
                stage2_valid <= '0';
                R_sum <= (others => '0');
                G_sum <= (others => '0');
                B_sum <= (others => '0'); 
                R_avg <= (others => '0');
                G_avg <= (others => '0');
                B_avg <= (others => '0');
                Gray_sum <= (others => '0');
                Gray_avg <= (others => '0');
                mult_result <= (others => '0');

                
                -- Reset outputs
                R_avg_o <= (others => '0');
                G_avg_o <= (others => '0');
                B_avg_o <= (others => '0');
                Gray_avg_o <= (others => '0');
                
            elsif pixel_valid = '1' then

                R_sum <= R_sum + unsigned(R_i);
                G_sum <= G_sum + unsigned(G_i);
                B_sum <= B_sum + unsigned(B_i);
               
            else

                stage1_valid <= frame_done;
                stage2_valid <= stage1_valid;
                stage3_valid <= stage2_valid;



                if frame_done = '1' then

                    R_avg <= R_sum * to_unsigned(435, 9);
                    G_avg <= G_sum * to_unsigned(435, 9);
                    B_avg <= B_sum * to_unsigned(435, 9);

                end if;


                if stage1_valid = '1' then 
                
                    Gray_sum <= resize(R_avg(34 downto 27), 10) + resize(G_avg(34 downto 27), 10) + resize(B_avg(34 downto 27), 10);

                    R_avg_o <= std_logic_vector(R_avg(34 downto 27));
                    G_avg_o <= std_logic_vector(G_avg(34 downto 27));
                    B_avg_o <= std_logic_vector(B_avg(34 downto 27));


                end if;

                
                if stage2_valid = '1' then
                
                    mult_result <= Gray_sum * to_unsigned(10923, 15);

                end if;
                
                if stage3_valid = '1' then
                    Gray_avg <= mult_result(24 downto 15);
                    Gray_avg_o <= std_logic_vector(mult_result(24 downto 15));

                    R_sum <= (others => '0');
                    G_sum <= (others => '0');
                    B_sum <= (others => '0');
                end if;  
            end if;    

        end if;
    end process;

end Behavioral;