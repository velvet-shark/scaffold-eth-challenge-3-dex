import { PageHeader } from "antd";
import React from "react";

// displays a page header

export default function Header() {
  return (
    <a href="https://github.com/austintgriffith/scaffold-eth" target="_blank" rel="noopener noreferrer">
      <PageHeader
        title="⚖️ Minimum Viable DEX"
        subTitle="The simples decentralized exchange example. Trade Ξ ETH for 🎈 balloons"
        style={{ cursor: "pointer" }}
      />
    </a>
  );
}
