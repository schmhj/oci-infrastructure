#!/usr/bin/env python3
"""Cross-tenancy OKE architecture diagram — Tenant A (acceptor) + Tenant B (requestor).

Two VCNs side-by-side with LPG peering, OKE node pools, gateways,
block volumes (tenant-b workload), and shared OCI services.

Usage:
    python3 generate_tenant_a_drawio.py [output_path]
"""
from __future__ import annotations

import sys
from pathlib import Path

from drawio_builder import (
    DrawioBuilder, add_icons_to_map,
    ICON_H, LABEL_GAP, LABEL_H,
)

# ---------------------------------------------------------------------------
# Icons beyond the default ICON_MAP
# ---------------------------------------------------------------------------
add_icons_to_map({
    "oke": "developer_services/developer_services_container_engine_for_kubernetes.svg",
    "rpg": "networking/networking_remote_peering_gateway.svg",
})

# ---------------------------------------------------------------------------
# Shared layout constants
# ---------------------------------------------------------------------------
PAD = 20
GAP = 20
ICON_SLOT = 150            # horizontal spacing between icon centres
HEADER = 40                # container title height
FOOTER = 20                # padding below last child
ROW = 50                   # icon row y-offset inside a leaf container
ICON_ROW = ICON_H + LABEL_GAP + LABEL_H   # 142 px
ONE_ROW = HEADER + ICON_ROW + FOOTER      # 202 px — height for a 1-icon-row container

# ---- container widths -------------------------------------------------------
PUB_W = PAD + 3 * ICON_SLOT + PAD           #  490 — IGW + NLB + OKE API
PRIV_W = PAD + 4 * ICON_SLOT + PAD          #  640 — NAT + SGW + 2× VM
LPG_W = PAD + 1 * ICON_SLOT + PAD           #  190 — single LPG icon
BLK_W = PAD + 2 * ICON_SLOT + PAD           #  340 — 2× block volume
VCN_W = PAD + max(PUB_W, PRIV_W, LPG_W, BLK_W) + PAD  #  680

# ---- VCN-A (acceptor) — 3 rows ----------------------------------------------
VCN_A_H = HEADER + 3 * ONE_ROW + 2 * GAP + FOOTER  # 706

# ---- VCN-B (requestor) — 4 rows (extra row for block volumes) ---------------
VCN_B_H = HEADER + 4 * ONE_ROW + 3 * GAP + FOOTER  # 928

# ---- Services panel — 4 icons in a 2×2 grid ---------------------------------
SVC_COLS = 2
SVC_W = PAD + SVC_COLS * ICON_SLOT + PAD    # 340
SVC_H = HEADER + 2 * ICON_ROW + FOOTER       # 344

# ---- Region: VCN-A | VCN-B | Services ---------------------------------------
VCN_A_X = PAD                                # 20
VCN_A_Y = HEADER                             # 40
VCN_B_X = VCN_A_X + VCN_W + GAP              # 720
VCN_B_Y = HEADER                             # 40
SVC_X = VCN_B_X + VCN_W + GAP                # 1420
SVC_Y = HEADER                               # 40

REGION_W = SVC_X + SVC_W + PAD               # 1780
REGION_H = HEADER + max(VCN_A_H, VCN_B_H, SVC_H) + FOOTER  # 40+928+20 = 988

# ---- Page -------------------------------------------------------------------
TITLE_H = 36
TITLE_X, TITLE_Y = PAD, 10
REGION_X, REGION_Y = PAD, TITLE_Y + TITLE_H + GAP  # 20, 66
PAGE_W = max(PAD + REGION_W + PAD, 1850)
PAGE_H = max(REGION_Y + REGION_H + PAD, 1100)

# ---- Edge label style (white text on dark chip) -----------------------------
EDGE_EXTRA = "fontColor=#FFFFFF;labelBackgroundColor=#312D2A;"


# ============================================================================
def _build_internet_edges(d, inet, igw, oke_api, parent):
    """Dashed user-interaction edges inside a public subnet."""
    return [
        d.add_edge(inet, igw, "", parent=parent, dashed=True,
                   style_extra=EDGE_EXTRA),
        d.add_edge(inet, oke_api, "", parent=parent, dashed=True,
                   style_extra=EDGE_EXTRA),
    ]


def _build_private_edges(d, vm1, vm2, nat, sgw, inet, parent):
    """4 leftward waypoint-routed edges + NAT→Internet, all in private subnet.

    Each of the 4 VM→gateway edges uses a unique y-level waypoint:
        vm1→nat  at y=8    (above icons)
        vm2→sgw  at y=22   (above icons, offset)
        vm1→sgw  at y=165  (below icons)
        vm2→nat  at y=180  (below icons, offset)

    vm1 is the left VM (x-centre ≈357), vm2 is the right VM (x-centre ≈507).
    """
    edges = []

    # vm1 → NAT — above, y=8
    edges.append(d.add_edge(
        vm1, nat, "Egress", parent=parent,
        exit_x=0.5, exit_y=0.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(357, 8), (57, 8)],
        style_extra=EDGE_EXTRA,
    ))
    # vm2 → NAT — below, y=180
    edges.append(d.add_edge(
        vm2, nat, "", parent=parent,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=1.0,
        waypoints=[(507, 180), (57, 180)],
        style_extra=EDGE_EXTRA,
    ))
    # vm1 → SGW — below, y=165
    edges.append(d.add_edge(
        vm1, sgw, "", parent=parent,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=1.0,
        waypoints=[(357, 165), (207, 165)],
        style_extra=EDGE_EXTRA,
    ))
    # vm2 → SGW — above, y=22
    edges.append(d.add_edge(
        vm2, sgw, "", parent=parent,
        exit_x=0.5, exit_y=0.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(507, 22), (207, 22)],
        style_extra=EDGE_EXTRA,
    ))
    # NAT → Internet label
    edges.append(d.add_edge(nat, inet, "", parent=parent,
                            style_extra=EDGE_EXTRA))
    return edges


# ============================================================================
def build(out_path: Path) -> None:
    d = DrawioBuilder(
        page_name="Cross-Tenancy OKE — LPG Peering",
        width=PAGE_W, height=PAGE_H,
    )

    # ---- Title ---------------------------------------------------------------
    d.add_text(
        "<b>newyeti — Cross-Tenancy OKE Clusters with LPG Peering (Ashburn)</b><br/>"
        "<i>us-ashburn-1 &nbsp;|&nbsp; "
        "Tenant A: oke-prod-tenant-a (v1.36.1, acceptor) &nbsp;|&nbsp; "
        "Tenant B: oke-prod-tenant-b (v1.36.1, requestor)</i>",
        x=TITLE_X, y=TITLE_Y, w=1400, h=TITLE_H,
        font_size=13, font_style=1,
    )

    # ---- Region --------------------------------------------------------------
    region = d.add_group(
        "Region: Ashburn (us-ashburn-1)",
        REGION_X, REGION_Y, REGION_W, REGION_H,
        group_type="region",
    )

    # ========================================================================
    #  VCN-A  (acceptor)
    # ========================================================================
    vcn_a = d.add_group(
        "VCN-A: vcn-schmhj-us-ashburn-1 &nbsp;(10.1.0.0/16) &nbsp;—&nbsp; Acceptor",
        VCN_A_X, VCN_A_Y, VCN_W, VCN_A_H,
        parent=region, group_type="vcn",
    )

    # -- Public Subnet A -------------------------------------------------------
    pub_a = d.add_group(
        "Public Subnet: snet-pub &nbsp;(10.1.0.0/24)",
        PAD, HEADER, PUB_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    igw_a = d.add_icon("Internet Gateway", "internet_gateway",
                       PAD, ROW, parent=pub_a,
                       tooltip="oci_core_internet_gateway — default route 0.0.0.0/0")
    nlb_a = d.add_icon("Network Load Balancer", "load_balancer",
                       PAD + ICON_SLOT, ROW, parent=pub_a,
                       tooltip="oci_network_load_balancer\nTCP 443 → node port 30443")
    oke_a = d.add_icon("OKE API Endpoint", "oke",
                       PAD + 2 * ICON_SLOT, ROW, parent=pub_a,
                       tooltip="oci_containerengine_cluster\nPublic API endpoint :6443")
    inet_a = d.add_text("<i>Internet</i>", PAD, ROW - 30, w=70, h=20,
                        parent=pub_a, font_size=9, font_style=2, align="center")

    # -- Private Subnet A ------------------------------------------------------
    PRIV_A_Y = HEADER + ONE_ROW + GAP  # 262
    priv_a = d.add_group(
        "Private Subnet: snet-priv &nbsp;(10.1.1.0/24)",
        PAD, PRIV_A_Y, PRIV_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    nat_a = d.add_icon("NAT Gateway", "nat_gateway",
                       PAD, ROW, parent=priv_a,
                       tooltip="oci_core_nat_gateway — default route 0.0.0.0/0")
    sgw_a = d.add_icon("Service Gateway", "service_gateway",
                       PAD + ICON_SLOT, ROW, parent=priv_a,
                       tooltip="oci_core_service_gateway — all OCI services in region")
    infra_a = d.add_icon(
        "Infra Node Pool", "vm",
        PAD + 2 * ICON_SLOT, ROW, parent=priv_a,
        tooltip="np-schmhj-us-ashburn-1-infra\n"
                "1 node · VM.Standard.A1.Flex · 1 OCPU / 8 GB\n"
                "Taint: tier=infra:NoSchedule",
        metadata={"pool": "infra", "nodes": "1"},
    )
    work_a = d.add_icon(
        "Workload Node Pool", "vm",
        PAD + 3 * ICON_SLOT, ROW, parent=priv_a,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "1 node · VM.Standard.A1.Flex · 3 OCPUs / 16 GB\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "1"},
    )
    inet_priv_a = d.add_text("<i>Internet</i>", PAD, ROW - 30, w=70, h=20,
                             parent=priv_a, font_size=9, font_style=2, align="center")

    # -- LPG Acceptor row A ----------------------------------------------------
    LPG_A_Y = PRIV_A_Y + ONE_ROW + GAP  # 484
    lpg_row_a = d.add_group(
        "LPG (Acceptor)",
        PAD, LPG_A_Y, LPG_W, ONE_ROW,
        parent=vcn_a, group_type="subnet",
    )
    lpg_a = d.add_icon("Local Peering Gateway", "rpg",
                       PAD, ROW, parent=lpg_row_a,
                       tooltip="oci_core_local_peering_gateway — acceptor\n"
                               "Accepts connection from tenant-b\n"
                               "Routes 10.2.0.0/16 via LPG")

    # ========================================================================
    #  VCN-B  (requestor)
    # ========================================================================
    vcn_b = d.add_group(
        "VCN-B: vcn-schmhj-us-ashburn-1 &nbsp;(10.2.0.0/16) &nbsp;—&nbsp; Requestor",
        VCN_B_X, VCN_B_Y, VCN_W, VCN_B_H,
        parent=region, group_type="vcn",
    )

    # -- Public Subnet B -------------------------------------------------------
    pub_b = d.add_group(
        "Public Subnet: snet-pub &nbsp;(10.2.0.0/24)",
        PAD, HEADER, PUB_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    igw_b = d.add_icon("Internet Gateway", "internet_gateway",
                       PAD, ROW, parent=pub_b,
                       tooltip="oci_core_internet_gateway — default route 0.0.0.0/0")
    nlb_b = d.add_icon("Network Load Balancer", "load_balancer",
                       PAD + ICON_SLOT, ROW, parent=pub_b,
                       tooltip="oci_network_load_balancer\nTCP 443 → node port 30443")
    oke_b = d.add_icon("OKE API Endpoint", "oke",
                       PAD + 2 * ICON_SLOT, ROW, parent=pub_b,
                       tooltip="oci_containerengine_cluster\nPublic API endpoint :6443")
    inet_b = d.add_text("<i>Internet</i>", PAD, ROW - 30, w=70, h=20,
                        parent=pub_b, font_size=9, font_style=2, align="center")

    # -- Private Subnet B ------------------------------------------------------
    PRIV_B_Y = HEADER + ONE_ROW + GAP  # 262
    priv_b = d.add_group(
        "Private Subnet: snet-priv &nbsp;(10.2.1.0/24)",
        PAD, PRIV_B_Y, PRIV_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    nat_b = d.add_icon("NAT Gateway", "nat_gateway",
                       PAD, ROW, parent=priv_b,
                       tooltip="oci_core_nat_gateway — default route 0.0.0.0/0")
    sgw_b = d.add_icon("Service Gateway", "service_gateway",
                       PAD + ICON_SLOT, ROW, parent=priv_b,
                       tooltip="oci_core_service_gateway — all OCI services in region")
    wk1_b = d.add_icon(
        "Workload Node 1", "vm",
        PAD + 2 * ICON_SLOT, ROW, parent=priv_b,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "2 nodes · VM.Standard.A1.Flex · 2 OCPUs / 12 GB each\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "2"},
    )
    wk2_b = d.add_icon(
        "Workload Node 2", "vm",
        PAD + 3 * ICON_SLOT, ROW, parent=priv_b,
        tooltip="np-schmhj-us-ashburn-1-workload\n"
                "2 nodes · VM.Standard.A1.Flex · 2 OCPUs / 12 GB each\n"
                "Label: tier=workload",
        metadata={"pool": "workload", "nodes": "2"},
    )
    inet_priv_b = d.add_text("<i>Internet</i>", PAD, ROW - 30, w=70, h=20,
                             parent=priv_b, font_size=9, font_style=2, align="center")

    # -- Block Volumes row B ---------------------------------------------------
    BLK_B_Y = PRIV_B_Y + ONE_ROW + GAP  # 484
    blk_row_b = d.add_group(
        "Block Volumes",
        PAD, BLK_B_Y, BLK_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    blk1_b = d.add_icon(
        "Immich", "block_storage",
        PAD, ROW, parent=blk_row_b,
        tooltip="Immich: 50 GB — backups enabled\n"
                "Attached to Workload Node 1",
        metadata={"size": "50 GB", "app": "Immich", "backup": "enabled"},
    )
    blk2_b = d.add_icon(
        "PostgreSQL", "block_storage",
        PAD + ICON_SLOT, ROW, parent=blk_row_b,
        tooltip="PostgreSQL: 50 GB — backups enabled\n"
                "Attached to Workload Node 2",
        metadata={"size": "50 GB", "app": "PostgreSQL", "backup": "enabled"},
    )

    # -- LPG Requestor row B ---------------------------------------------------
    LPG_B_Y = BLK_B_Y + ONE_ROW + GAP  # 706
    lpg_row_b = d.add_group(
        "LPG (Requestor)",
        PAD, LPG_B_Y, LPG_W, ONE_ROW,
        parent=vcn_b, group_type="subnet",
    )
    lpg_b = d.add_icon("Local Peering Gateway", "rpg",
                       PAD, ROW, parent=lpg_row_b,
                       tooltip="oci_core_local_peering_gateway — requestor\n"
                               "Initiates connection to tenant-a LPG\n"
                               "Routes 10.1.0.0/16 via LPG")

    # ========================================================================
    #  OCI Services (shared, 2×2 grid)
    # ========================================================================
    services = d.add_group(
        "OCI Services",
        SVC_X, SVC_Y, SVC_W, SVC_H,
        parent=region, group_type="services",
    )
    vault = d.add_icon("Vault", "vault",
                       PAD, ROW, parent=services,
                       tooltip="OCI Vault — secrets management")
    devops = d.add_icon("DevOps", "devops",
                        PAD + ICON_SLOT, ROW, parent=services,
                        tooltip="OCI DevOps — CI/CD pipelines")
    logging_icon = d.add_icon("Logging", "logging",
                              PAD, ROW + ICON_ROW, parent=services,
                              tooltip="OCI Logging — centralized log aggregation")
    ocir = d.add_icon("Container Registry", "container_registry",
                      PAD + ICON_SLOT, ROW + ICON_ROW, parent=services,
                      tooltip="OCI Registry (OCIR) — container images")

    # ========================================================================
    #  EDGES
    # ========================================================================
    all_edges = []

    # ---- VCN-A edges ---------------------------------------------------------
    all_edges += _build_internet_edges(d, inet_a, igw_a, oke_a, pub_a)
    all_edges += _build_private_edges(d, infra_a, work_a, nat_a, sgw_a,
                                      inet_priv_a, priv_a)
    # NLB → VMs (cross-subnet, parent=vcn_a; router fans these out cleanly)
    all_edges.append(d.add_edge(nlb_a, infra_a, "TCP 30443", parent=vcn_a,
                                style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(nlb_a, work_a, "", parent=vcn_a,
                                style_extra=EDGE_EXTRA))

    # ---- VCN-B edges ---------------------------------------------------------
    all_edges += _build_internet_edges(d, inet_b, igw_b, oke_b, pub_b)
    all_edges += _build_private_edges(d, wk1_b, wk2_b, nat_b, sgw_b,
                                      inet_priv_b, priv_b)
    # NLB → VMs
    all_edges.append(d.add_edge(nlb_b, wk1_b, "TCP 30443", parent=vcn_b,
                                style_extra=EDGE_EXTRA))
    all_edges.append(d.add_edge(nlb_b, wk2_b, "", parent=vcn_b,
                                style_extra=EDGE_EXTRA))

    # Block-volume attachments (cross-row within vcn_b)
    # wk1→blk1: exit bottom, route down through a mid-gap then left to blk1
    all_edges.append(d.add_edge(
        wk1_b, blk1_b, "", parent=vcn_b,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(377, 380), (77, 380)],
        style_extra=EDGE_EXTRA,
    ))
    # wk2→blk2: exit bottom, route down through a different mid-gap then left
    all_edges.append(d.add_edge(
        wk2_b, blk2_b, "", parent=vcn_b,
        exit_x=0.5, exit_y=1.0, entry_x=0.5, entry_y=0.0,
        waypoints=[(527, 400), (227, 400)],
        style_extra=EDGE_EXTRA,
    ))

    # ---- Cross-VCN LPG peering (parent=region) -------------------------------
    all_edges.append(d.add_edge(
        lpg_a, lpg_b, "LPG Peering\n10.1.0.0/16 ↔ 10.2.0.0/16",
        parent=region,
        style_extra=EDGE_EXTRA,
    ))

    # ========================================================================
    #  Overlap gate, write, report
    # ========================================================================
    problems = d.check_overlaps()
    if problems:
        for p in problems:
            print(p)
        raise SystemExit(1)

    d.write(out_path)
    size_kb = out_path.stat().st_size / 1024
    print(
        f"{out_path} | page {PAGE_W}x{PAGE_H} | "
        f"{len(all_edges)} edges | {size_kb:.1f} KB"
    )


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tenant_a_oke_deepdive.drawio")
    build(out)
