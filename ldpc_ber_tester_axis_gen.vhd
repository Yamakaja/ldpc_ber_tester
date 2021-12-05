library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

entity ldpc_ber_tester_axis_gen is
    generic (
        SEED_ID         : integer := 0;
        COUNTER_WIDTH   : integer := 6
    );
    port (
        clk             : in  std_logic;                        --! Clock input
        resetn          : in  std_logic;                        --! Asynchronous inverted reset
        en              : in  std_logic;                        --! Clock enable
        sw_resetn       : in  std_logic;                        --! Software Reset Input

        factor          : in  std_logic_vector(15 downto 0);    --! The factor input, may change arbitrarily
        offset          : in  std_logic_vector(7 downto 0);     --! Offset input from regmap
        din_beats       : in  std_logic_vector(15 downto 0);    --! How many beats the AXIS transaction should have

        ctrl_tvalid     : out std_logic;                        --! CTRL Stream
        ctrl_tready     : in std_logic;                         --! CTRL Stream

        din_tready      : in  std_logic;                        --! AXIS Stream
        din_tvalid      : out std_logic;                        --! AXIS Stream
        din_tdata       : out std_logic_vector(127 downto 0);   --! AXIS Stream
        din_tlast       : out std_logic;                        --! AXIS Stream

        status_tvalid   : in std_logic;
        status_tready   : out std_logic;
        status_tdata    : in std_logic_vector(31 downto 0);

        dout_finish     : in std_logic;                         --! Indicates the completion of a DOUT block

        finished_blocks : out std_logic_vector(63 downto 0);    --! How many blocks have been processed
        in_flight       : out std_logic_vector(31 downto 0);    --! The submitted amount of blocks minus the finished amount, should never exceed 16 or so
        last_status     : out std_logic_vector(31 downto 0)     --! Last status from SD-FEC Core. For debugging purposes

    );
end ldpc_ber_tester_axis_gen;

architecture beh of ldpc_ber_tester_axis_gen is

    component grng_16 is
        generic (
            xoro_seed_base : integer := 0                           --! The seed base is an index into an array of seeds that will be used to initialize the uniform random number generators of this core. To avoid seed duplication, increment this value by one for each instance of this core in your design!
            );
        port (
            clk         : in std_logic;                             --! Clock in
            resetn      : in std_logic;                             --! Inverted Reset
            en          : in std_logic;                             --! Enable
            data        : out std_logic_vector(8*16 - 1 downto 0);  --! Remapped data output
            
            factor      : in std_logic_vector(15 downto 0);         --! sigma of normal distribution
            offset      : in std_logic_vector( 7 downto 0)          --! mu    of normal distribution
        );
    end component;

    type t_state is (IDLE, INITIALIZING, RUNNING);
    signal r_state          : t_state;

    signal r_valid_counter  : unsigned(COUNTER_WIDTH - 1 downto 0);
    signal r_axis_tdata     : std_logic_vector(din_tdata'range);
    signal r_axis_tvalid    : std_logic;
    signal r_axis_tlast     : std_logic;
    signal r_din_beats      : unsigned(15 downto 0);
    signal r_beat_counter   : unsigned(15 downto 0);
    signal r_factor         : std_logic_vector(15 downto 0);
    signal r_offset         : std_logic_vector(7 downto 0);

    signal r_finished_blocks: unsigned(63 downto 0);
    signal r_in_flight      : unsigned(31 downto 0);
    signal r_ctrl_vs_din    : unsigned(6 downto 0);
    signal r_ctrl_tvalid    : std_logic;
    signal r_status_tready  : std_logic;

    signal r_last_status    : std_logic_vector(31 downto 0);

    signal w_sub_en         : std_logic;
    signal w_remapped       : std_logic_vector(8*16 - 1 downto 0);

    signal w_running        : std_logic;
    signal w_din_finish     : std_logic;

    signal w_sub_clk        : std_logic;

begin

    finished_blocks <= std_logic_vector(r_finished_blocks);
    in_flight       <= std_logic_vector(r_in_flight);
    ctrl_tvalid     <= r_ctrl_tvalid;
    status_tready   <= r_status_tready;
    last_status     <= r_last_status;

    w_running       <= or_reduce(std_logic_vector(r_ctrl_vs_din));
    w_din_finish    <= r_axis_tvalid and r_axis_tlast and din_tready;

    stats : process (clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' or sw_resetn = '0' then
                r_finished_blocks   <= (others => '0');            
                r_in_flight         <= (others => '0');
                r_ctrl_vs_din       <= (others => '0');
                r_ctrl_tvalid       <= '0';
                r_status_tready     <= '1';
                r_last_status       <= (others => '0');
            else
                r_status_tready <= '1';

                -- Keep amount of ctrl requests that are in-flight below 4
                r_ctrl_tvalid <= (en and not or_reduce(std_logic_vector(r_in_flight(31 downto 2))))
                                 or (r_ctrl_tvalid and (not ctrl_tready));

                if r_status_tready = '1' and status_tvalid = '1' then
                    r_finished_blocks   <= r_finished_blocks + 1;
                    r_last_status       <= status_tdata;
                end if;
                
                -- Transactions start with a CTRL word to provide information
                -- about the contents of the DIN stream. Once the data has been
                -- processed we receive a CTRL beat and data on DOUT. We consider
                -- the last beat of DOUT the be the end of a transaction.
                if ((r_ctrl_tvalid and ctrl_tready) xor dout_finish) = '1' then
                    if dout_finish = '1' then
                        r_in_flight <= r_in_flight - 1;
                    else
                        r_in_flight <= r_in_flight + 1;
                    end if;
                    -- TODO: Enable VHDL 2008 support .-.
                end if;

                -- Again, in-flight tracking but only for CTRL to DIN
                if ((r_ctrl_tvalid and ctrl_tready) xor w_din_finish) = '1' then
                    if w_din_finish = '1' then
                        r_ctrl_vs_din <= r_ctrl_vs_din - 1;
                    else
                        r_ctrl_vs_din <= r_ctrl_vs_din + 1;
                    end if;
                    -- TODO: VHDL 2008 ...
                end if;
            end if;
        end if;
    end process stats;

--  BUFGCE_inst : BUFGCE
--      generic map (
--         CE_TYPE => "SYNC",               -- ASYNC, HARDSYNC, SYNC
--         IS_CE_INVERTED => '0',           -- Programmable inversion on CE
--         IS_I_INVERTED => '0',            -- Programmable inversion on I
--         SIM_DEVICE => "ULTRASCALE_PLUS"  -- ULTRASCALE, ULTRASCALE_PLUS
--      )
--      port map (
--         O    => w_sub_clk,
--         CE   => w_sub_en,
--         I    => clk
--      );

--  i_grng : grng_16
--      generic map (
--          xoro_seed_base => SEED_ID
--      )
--      port map (
--          clk     => w_sub_clk,
--          resetn  => resetn,
--          en      => '1',
--          data    => w_remapped,
--          factor  => r_factor,
--          offset  => r_offset
--      );

    i_grng : grng_16
        generic map (
            xoro_seed_base => SEED_ID
        )
        port map (
            clk     => clk,
            resetn  => resetn,
            en      => w_sub_en,
            data    => w_remapped,
            factor  => r_factor,
            offset  => r_offset
        );

    -- The idea behind this core:
    -- The "*_axis_gen" module is reponsible for controlling the boxmuller,
    -- xoroshiro and remapping cores, and converting their outputs into something
    -- that can be fed into the SD-FEC cores. This results in a couple constraints
    -- which have to be kept in mind:
    --
    -- * The boxmuller cores, and by extension the output_remapper, produce junk
    --   while registers are still uninitialized and the pipeline is being flushed,
    --   consequently the it is the responsibility of this core to make sure those
    --   invalid samples never make it to the output.
    -- * The SD-FEC always works in blocks of din_beats input beats, and stopping
    --   the output stream with some data still in on the fly could result in bad
    --   data making it into the next test. Thus this block doesn't treat `en` as
    --   a traditional clock enable, but rather as a suggestion as to when no new
    --   transactions should be started.
    -- * Additionally, over the course of one of such blocks the factor and offset
    --   values must be kept stable!
    --
    -- These conditions make a simple state machine the tool of choice for this scenario:
    -- We introduce four states:
    --
    -- * IDLE: In this state the module is waiting for the enable signal to go high,
    --         and thus indicate that the configuration inputs have been initialized.
    --         Once en has gone high, the state transitions into INITIALIZING.
    -- * INITIALIZING: In this state the output valid is still held and the random
    --         number generator cores are given some cycles to flush the pipelines.
    --         The state will automatically transition to RUNNING after 64 cycles.
    -- * RUNNING: Here the output is finally enabled and samples are allowed to
    --         flow. Internally, the current position inside of a block is kept
    --         track of using r_beat_counter, which wraps around when reaching
    --         din_beats. Once en goes low the state is transitioned to ENDING.

    -- Output driving registers
    din_tdata   <= r_axis_tdata;
    din_tvalid  <= r_axis_tvalid;
    din_tlast   <= r_axis_tlast;

    w_sub_en <= '1' when r_state /= IDLE or w_running = '1' else '0';
--  w_sub_en <= '1' when r_state /= IDLE or w_running = '1' or resetn = '0' else '0';

    state_machine : process (clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' or sw_resetn = '0' then
                r_state         <= IDLE;
                r_valid_counter <= (others => '0');
                r_axis_tdata    <= (others => '0');
                r_axis_tvalid   <= '0';
                r_axis_tlast    <= '0';
                r_beat_counter  <= (others => '0');
                r_din_beats     <= (others => '0');
                r_factor        <= (others => '0');
                r_offset        <= (others => '0');
            else
                case r_state is
                    when IDLE =>
                        if w_running = '1' then
                            r_state <= INITIALIZING;

                            r_factor <= factor;
                            r_offset <= offset;
                            r_valid_counter <= (others => '0');
                            r_din_beats <= unsigned(din_beats);
                        end if;

                    when INITIALIZING =>
                        r_valid_counter <= r_valid_counter + 1;

                        if w_running = '0' then
                            r_state <= IDLE;
                        elsif and_reduce(std_logic_vector(r_valid_counter)) = '1' then
                            r_state <= RUNNING;

                            r_beat_counter <= (others => '0');
                            r_axis_tvalid <= '1';
                            r_axis_tdata <= w_remapped;
                        end if;

                    when RUNNING =>
                        r_axis_tvalid <= '1';

                        if r_axis_tvalid = '1' and din_tready = '1' then
                            -- Enable tlast on last beat
                            if r_beat_counter + 2 = r_din_beats then
                                r_axis_tlast <= '1';
                            else
                                r_axis_tlast <= '0';
                            end if;
                            r_axis_tdata <= w_remapped;

                            if r_axis_tlast = '1' then
                                -- Going low for one cycle
                                r_beat_counter <= (others => '0');
                                r_axis_tlast <= '0';
                                r_axis_tvalid <= '0';

                                if en = '0' and r_ctrl_vs_din = 1 then
                                    r_state <= IDLE;
                                end if;
                            else
                                r_beat_counter <= r_beat_counter + 1;
                            end if;
                        end if;

                    when others =>
                        r_state <= IDLE;
                end case;
            end if;
        end if;
    end process state_machine;

end beh;
