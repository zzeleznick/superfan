import React from "react";

export function Button({onClick, text}) {
  return (
    <div
      style={{
        backgroundColor: "#cd4337",
        border: "none",
        borderRadius: "8px",
        color: "#fff",
        boxShadow: "0px 0px 10px 6px rgba(200, 200, 255, 0.75)",
        cursor: "pointer",
        fontSize: "22px",
        textAlign: "center",
        textDecoration: "none",
        margin: "10px 20px",
        padding: "12px 24px",
        whiteSpace: "nowrap",
        }}
    >
      <div className="Button" onClick={onClick}> {text} </div>
    </div>
  );
}

  