-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- 
-- =============================================================================
-- Authors:					Patrick Lehmann
--									Steffen Koehler
--
-- Module:					Synchronizes a strobe signal across clock-domain boundaries
--
-- Description:
-- ------------------------------------
--		This module synchronizes multiple high-active bits from clock-domain
--		'Clock1' to clock-domain 'Clock2'. The clock-domain boundary crossing is
--		done by a T-FF, two synchronizer D-FFs and a reconstructive XOR. A busy
--		flag is additionally calculated and can be used to block new inputs. All
--		bits are independent from each other. Multiple consecutive strobes are
--		suppressed by a rising edge detection.
-- 
--		ATTENTION:
--			Use this synchronizer only for one-cycle high-active signals (strobes).
--		
--		CONSTRAINTS:
--			General:
--				This module uses sub modules which need to be constrained. Please
--				attend to the notes of the instantiated sub modules.
--			
-- License:
-- =============================================================================
-- Copyright 2007-2015 Technische Universitaet Dresden - Germany
--										 Chair for VLSI-Design, Diagnostics and Architecture
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--		http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- =============================================================================

library IEEE;
use			IEEE.STD_LOGIC_1164.all;
use			IEEE.NUMERIC_STD.all;

library PoC;


entity sync_Strobe IS
  generic (
	  BITS								: POSITIVE		:= 1;														-- number of bit to be synchronized
		GATED_INPUT_BY_BUSY	: BOOLEAN			:= TRUE													-- use gated input (by busy signal)
	);
  port (
		Clock1							: in	STD_LOGIC;															-- <Clock>	input clock domain
		Clock2							: in	STD_LOGIC;															-- <Clock>	output clock domain
		Input								: in	STD_LOGIC_VECTOR(BITS - 1 downto 0);		-- @Clock1:	input bits
		Output							: out STD_LOGIC_VECTOR(BITS - 1 downto 0);		-- @Clock2:	output bits
		Busy								: out	STD_LOGIC_VECTOR(BITS - 1 downto 0)			-- @Clock1:	busy bits
	);
end;


architecture rtl of sync_Strobe is
	attribute SHREG_EXTRACT										: STRING;

	signal syncClk1_In		: STD_LOGIC_VECTOR(BITS - 1 downto 0);
	signal syncClk1_Out		: STD_LOGIC_VECTOR(BITS - 1 downto 0);
	signal syncClk2_In		: STD_LOGIC_VECTOR(BITS - 1 downto 0);
	signal syncClk2_Out		: STD_LOGIC_VECTOR(BITS - 1 downto 0);
	
BEGIN

	gen : for i in 0 to BITS - 1 generate
		signal D0							: STD_LOGIC			:= '0';
		signal T1							: STD_LOGIC			:= '0';
		signal D2							: STD_LOGIC			:= '0';

		signal Changed_Clk1		: STD_LOGIC;
		signal Changed_Clk2		: STD_LOGIC;
		signal Busy_i					: STD_LOGIC;
		
		-- Prevent XST from translating two FFs into SRL plus FF
		attribute SHREG_EXTRACT OF D0	: signal is "NO";
		attribute SHREG_EXTRACT OF T1	: signal is "NO";
		attribute SHREG_EXTRACT OF D2	: signal is "NO";
		
	begin
		
		process(Clock1)
		begin
			if rising_edge(Clock1) then
				-- input delay for rising edge detection
				D0		<= Input(I);
			
				-- T-FF to converts a strobe to a flag signal
				if (GATED_INPUT_BY_BUSY = TRUE) then
					T1	<= (Changed_Clk1 and not Busy_i) xor T1;
				else
					T1	<= Changed_Clk1 xor T1;
				end if;
			end if;
		end process;
		
		-- D-FF for level change detection (both edges)
		D2	<= syncClk2_Out(I) when rising_edge(Clock2);

		-- assign syncClk*_In signals
		syncClk2_In(I)	<= T1;
		syncClk1_In(I)	<= syncClk2_Out(I);	-- D2

		Changed_Clk1		<= not D0 and Input(I);				-- rising edge detection
		Changed_Clk2		<= syncClk2_Out(I) xor D2;		-- level change detection; restore strobe signal from flag
		Busy_i					<= T1 xor syncClk1_Out(I);		-- calculate busy signal

		-- output signals
		Output(I)				<= Changed_Clk2;
		Busy(I)					<= Busy_i;
	end generate;
	
	syncClk2 : entity PoC.sync_Bits
		generic map (
			BITS				=> BITS						-- number of bit to be synchronized
		)
		port map (
			Clock				=> Clock2,				-- <Clock>	output clock domain
			Input				=> syncClk2_In,		-- @async:	input bits
			Output			=> syncClk2_Out		-- @Clock:	output bits
		);
	
	syncClk1 : entity PoC.sync_Bits
		generic map (
			BITS				=> BITS						-- number of bit to be synchronized
		)
		port map (
			Clock				=> Clock1,				-- <Clock>	output clock domain
			Input				=> syncClk1_In,		-- @async:	input bits
			Output			=> syncClk1_Out		-- @Clock:	output bits
		);
end;